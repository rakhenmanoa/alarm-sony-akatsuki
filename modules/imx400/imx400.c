// SPDX-License-Identifier: GPL-2.0
/*
 * Pilote V4L2 du capteur Sony IMX400 (caméra arrière du Xperia XZ3, module SOI20BS2).
 *
 * Aucun réglage de Sony n'est inclus ici : les séquences de registres (initialisation
 * du capteur, puis un bloc par mode) sont lues dans un fichier de firmware construit
 * à partir d'une capture faite sur le téléphone, sous LineageOS
 * (scripts/capturer-camera-adb.sh puis scripts/imx400-sequences.py).
 *
 * Le capteur a sa propre mémoire d'image : il lit la matrice bien plus vite qu'il
 * n'envoie les lignes. Les durées (exposition, image) suivent llp / pixel_rate,
 * comme dans les réglages de Sony ; link_freq décrit le lien CSI-2 (4 voies).
 *
 * Structure inspirée du pilote imx219 (Raspberry Pi) de Linux.
 */

#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/firmware.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/pm_runtime.h>
#include <linux/regulator/consumer.h>
#include <linux/slab.h>
#include <linux/unaligned.h>

#include <media/v4l2-cci.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>
#include <media/v4l2-fwnode.h>
#include <media/v4l2-mediabus.h>

#define IMX400_FIRMWARE_DEFAUT		"sony/imx400-akatsuki.bin"
#define IMX400_XCLK_SEQUENCES		8000000		/* horloge des séquences de Sony */

#define IMX400_REG_ID			CCI_REG16(0x0016)
#define IMX400_REG_MODE_SELECT		CCI_REG8(0x0100)
#define IMX400_REG_GROUP_HOLD		CCI_REG8(0x0104)
#define IMX400_REG_EXPOSURE		CCI_REG16(0x0202)
#define IMX400_REG_ANALOG_GAIN		CCI_REG16(0x0204)
#define IMX400_REG_DIG_GAIN_GR		CCI_REG16(0x020e)
#define IMX400_REG_DIG_GAIN_R		CCI_REG16(0x0210)
#define IMX400_REG_DIG_GAIN_B		CCI_REG16(0x0212)
#define IMX400_REG_DIG_GAIN_GB		CCI_REG16(0x0214)
#define IMX400_REG_FLL			CCI_REG16(0x0340)
#define IMX400_REG_WB_GR		CCI_REG16(0x0b8e)
#define IMX400_REG_WB_R			CCI_REG16(0x0b90)
#define IMX400_REG_WB_B			CCI_REG16(0x0b92)
#define IMX400_REG_WB_GB		CCI_REG16(0x0b94)

#define IMX400_FLL_MAX			0xffff
#define IMX400_FPS_DEFAUT		30
#define IMX400_EXPOSURE_MIN		1
#define IMX400_EXPOSURE_OFFSET		22	/* fll - exposition : 21 chez Sony */
#define IMX400_ANA_GAIN_MAX		960	/* 16x (gain = 1024 / (1024 - code)) */

/*
 * libcamera ne connaît pas l'IMX400 (pas de « camera sensor helper ») : il prend
 * alors la valeur du contrôle de gain pour le gain lui-même (×1 = 1). Avec les codes
 * du capteur (0…960) l'exposition automatique restait vers ×1, d'où des images 3 à 4
 * fois trop sombres. Par défaut, le contrôle est donc le gain entier (1…16) ; le
 * pilote le convertit en code. gain_codes=1 rend les codes bruts du capteur.
 */
static bool gain_codes;
module_param(gain_codes, bool, 0444);
MODULE_PARM_DESC(gain_codes, "gain analogique en codes du capteur (0…960) au lieu de ×1…×16");

static u32 imx400_code_gain(s32 val)
{
	if (gain_codes)
		return val;
	return 1024 - 1024 / clamp_t(s32, val, 1, 16);
}
#define IMX400_DGTL_GAIN_MIN		0x100
#define IMX400_DGTL_GAIN_MAX		0xfff
#define IMX400_DGTL_GAIN_DEFAULT	0x100

#define IMX400_NATIVE_WIDTH		5504
#define IMX400_NATIVE_HEIGHT		3808

#define IMX400_MAX_MODES		8

/*
 * CAMSS (SDM845) : la CSID remet l'horloge du VFE à 320 MHz puis exige
 * pixel_rate × bpp / 64 × 1,05 ≤ cette horloge, sinon « Failed to power up
 * pipeline: -16 » (13/10/2026). Avec les 2,667 Gpx/s du capteur il faudrait 437 MHz,
 * alors que le lien CSI-2 n'en transporte que 541 Mpx/s. On annonce donc un
 * pixel_rate plafonné et une longueur de ligne réduite d'autant : durée de ligne
 * (llp / pixel_rate) inchangée tant que la largeur le permet (modes avec binning) ;
 * en pleine définition la durée annoncée est un peu plus longue que la vraie.
 */
static unsigned int pixel_rate_max = 1900000000;
module_param(pixel_rate_max, uint, 0444);
MODULE_PARM_DESC(pixel_rate_max, "pixel_rate maximal annoncé (Hz), défaut 1,9 GHz");

static const char * const imx400_supply_name[] = {
	"vana",		/* 2,8 V analogique */
	"vif",		/* 1,8 V E/S */
	"vaf",		/* 2,7 V autofocus / OIS */
};
#define IMX400_NUM_SUPPLIES ARRAY_SIZE(imx400_supply_name)

struct imx400_mode {
	char name[16];
	u32 width;
	u32 height;
	u32 llp;
	u32 fll;
	u32 fll_def;	/* cadence par défaut : 30 i/s au plus (expositions jusqu'à 33 ms) */
	struct v4l2_rect crop;
	u64 pixel_rate;
	u64 link_freq;
	const u8 *data;
	u32 len;
};

struct imx400 {
	struct v4l2_subdev sd;
	struct media_pad pad;
	struct regmap *regmap;
	struct clk *xclk;
	u32 xclk_freq;
	struct gpio_desc *reset_gpio;
	struct regulator_bulk_data supplies[IMX400_NUM_SUPPLIES];

	struct v4l2_ctrl_handler ctrl_handler;
	struct v4l2_ctrl *pixel_rate;
	struct v4l2_ctrl *link_freq;
	struct v4l2_ctrl *exposure;
	struct v4l2_ctrl *vblank;
	struct v4l2_ctrl *hblank;

	u8 *fw_data;
	struct imx400_mode init;
	struct imx400_mode modes[IMX400_MAX_MODES];
	unsigned int num_modes;
	s64 link_freq_menu[1];

	unsigned int max_chunk;
	bool init_done;
};

static inline struct imx400 *to_imx400(struct v4l2_subdev *sd)
{
	return container_of(sd, struct imx400, sd);
}

static const struct imx400_mode *imx400_mode_of(struct imx400 *imx400,
						const struct v4l2_mbus_framefmt *fmt)
{
	unsigned int i;

	for (i = 0; i < imx400->num_modes; i++)
		if (imx400->modes[i].width == fmt->width &&
		    imx400->modes[i].height == fmt->height)
			return &imx400->modes[i];
	return &imx400->modes[0];
}

/* -----------------------------------------------------------------------------
 * Séquences de registres
 */

/*
 * Les séquences supposent une horloge de 8 MHz ; le contrôleur d'horloge du SDM845
 * ne sait pas la produire (19,2 / 24 / 33,3 / 34,3 MHz). À 24 MHz, on divise par 3
 * à l'entrée des deux PLL : mêmes fréquences internes.
 */
static void imx400_corriger_horloge(struct imx400 *imx400, u16 reg, u8 *val, u8 n)
{
	u32 pre = imx400->xclk_freq / IMX400_XCLK_SEQUENCES;
	unsigned int i;

	for (i = 0; i < n; i++) {
		switch (reg + i) {
		case 0x0136:
			val[i] = imx400->xclk_freq / 1000000;
			break;
		case 0x0137:
			val[i] = (imx400->xclk_freq % 1000000) * 256 / 1000000;
			break;
		case 0x0305:	/* pre_pll_clk_div */
		case 0x030d:	/* op_pre_pll_clk_div */
			val[i] = val[i] * pre;
			break;
		}
	}
}

static int imx400_ecrire_bloc(struct imx400 *imx400, const struct imx400_mode *b)
{
	struct i2c_client *client = v4l2_get_subdevdata(&imx400->sd);
	u8 buf[2 + 255];
	u32 pos = 0;
	int ret;

	while (pos + 3 <= b->len) {
		u16 reg = get_unaligned_be16(b->data + pos);
		u8 n = b->data[pos + 2];
		unsigned int i;

		pos += 3;
		if (pos + n > b->len)
			return -EINVAL;
		memcpy(buf + 2, b->data + pos, n);
		imx400_corriger_horloge(imx400, reg, buf + 2, n);

		for (i = 0; i < n; i += imx400->max_chunk) {
			unsigned int c = min_t(unsigned int, n - i, imx400->max_chunk);
			u8 msg[2 + 255];

			put_unaligned_be16(reg + i, msg);
			memcpy(msg + 2, buf + 2 + i, c);
			ret = i2c_master_send(client, msg, 2 + c);
			if (ret != 2 + c) {
				dev_err(&client->dev, "%s : écriture 0x%04x échouée (%d)\n",
					b->name, reg + i, ret);
				return ret < 0 ? ret : -EIO;
			}
		}
		pos += n;
	}
	return 0;
}

static int imx400_charger_sequences(struct imx400 *imx400, const char *nom)
{
	struct i2c_client *client = v4l2_get_subdevdata(&imx400->sd);
	struct device *dev = &client->dev;
	const struct firmware *fw;
	u32 version, nblocs, pos, i;
	size_t taille;
	int ret;

	ret = request_firmware(&fw, nom, dev);
	if (ret)
		return dev_err_probe(dev, ret,
			"séquences %s absentes : les construire sous LineageOS (scripts/capturer-camera-adb.sh, scripts/imx400-sequences.py)\n",
			nom);

	taille = fw->size;
	imx400->fw_data = devm_kmemdup(dev, fw->data, taille, GFP_KERNEL);
	release_firmware(fw);
	if (!imx400->fw_data)
		return -ENOMEM;

	if (taille < 16 || memcmp(imx400->fw_data, "IMX400SQ", 8))
		goto invalide;
	version = get_unaligned_le32(imx400->fw_data + 8);
	nblocs = get_unaligned_le32(imx400->fw_data + 12);
	if (version != 1 || nblocs < 2)
		goto invalide;

	pos = 16;
	for (i = 0; i < nblocs; i++) {
		const u8 *h = imx400->fw_data + pos;
		struct imx400_mode *m;
		u32 len;

		if (pos + 44 > taille)
			goto invalide;
		len = get_unaligned_le32(h + 40);
		if (pos + 44 + len > taille)
			goto invalide;

		if (i == 0) {
			m = &imx400->init;
		} else {
			if (imx400->num_modes >= IMX400_MAX_MODES)
				break;
			m = &imx400->modes[imx400->num_modes++];
		}
		memcpy(m->name, h, 15);
		m->name[15] = 0;
		m->width = get_unaligned_le16(h + 16);
		m->height = get_unaligned_le16(h + 18);
		m->llp = get_unaligned_le16(h + 20);
		m->fll = get_unaligned_le16(h + 22);
		m->crop.left = get_unaligned_le16(h + 24);
		m->crop.top = get_unaligned_le16(h + 26);
		m->crop.width = get_unaligned_le16(h + 28) - m->crop.left + 1;
		m->crop.height = get_unaligned_le16(h + 30) - m->crop.top + 1;
		m->pixel_rate = get_unaligned_le32(h + 32);
		m->link_freq = get_unaligned_le32(h + 36);
		m->data = h + 44;
		m->len = len;
		pos += 44 + len;

		if (i == 0) {
			if (strcmp(m->name, "init"))
				goto invalide;
			continue;
		}
		if (!m->width || !m->height || m->llp < m->width || m->fll <= m->height ||
		    !m->pixel_rate || !m->link_freq ||
		    m->link_freq != imx400->modes[0].link_freq)
			goto invalide;
		m->fll_def = clamp_t(u32, div_u64(m->pixel_rate, (u64)m->llp * IMX400_FPS_DEFAUT),
				     m->fll, IMX400_FLL_MAX);
		if (pixel_rate_max && m->pixel_rate > pixel_rate_max) {
			u32 llp = div_u64((u64)m->llp * pixel_rate_max, m->pixel_rate);

			if (llp < m->width + 64) {
				dev_info(dev, "mode %s : durée de ligne annoncée approximative\n",
					 m->name);
				llp = m->width + 64;
			}
			m->llp = llp;
			m->pixel_rate = pixel_rate_max;
		}
		dev_info(dev, "mode %s : llp annoncée %u, fll %u (défaut %u), %u Mpx/s\n", m->name,
			 m->llp, m->fll, m->fll_def, (u32)div_u64(m->pixel_rate, 1000000));
	}
	return 0;

invalide:
	return dev_err_probe(dev, -EINVAL, "fichier de séquences %s invalide\n", nom);
}

/* -----------------------------------------------------------------------------
 * Contrôles
 */

static int imx400_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct imx400 *imx400 = container_of(ctrl->handler, struct imx400, ctrl_handler);
	struct i2c_client *client = v4l2_get_subdevdata(&imx400->sd);
	const struct v4l2_mbus_framefmt *format;
	struct v4l2_subdev_state *state;
	int ret = 0;

	state = v4l2_subdev_get_locked_active_state(&imx400->sd);
	format = v4l2_subdev_state_get_format(state, 0);

	if (ctrl->id == V4L2_CID_VBLANK) {
		int exposure_max = format->height + ctrl->val - IMX400_EXPOSURE_OFFSET;

		ret = __v4l2_ctrl_modify_range(imx400->exposure, imx400->exposure->minimum,
					       exposure_max, 1,
					       min(exposure_max, (int)imx400->exposure->default_value));
		if (ret)
			return ret;
	}

	if (pm_runtime_get_if_in_use(&client->dev) == 0)
		return 0;

	switch (ctrl->id) {
	case V4L2_CID_EXPOSURE:
		cci_write(imx400->regmap, IMX400_REG_EXPOSURE, ctrl->val, &ret);
		break;
	case V4L2_CID_ANALOGUE_GAIN:
		cci_write(imx400->regmap, IMX400_REG_ANALOG_GAIN, imx400_code_gain(ctrl->val),
			  &ret);
		break;
	case V4L2_CID_DIGITAL_GAIN:
		cci_write(imx400->regmap, IMX400_REG_GROUP_HOLD, 1, &ret);
		cci_write(imx400->regmap, IMX400_REG_DIG_GAIN_GR, ctrl->val, &ret);
		cci_write(imx400->regmap, IMX400_REG_DIG_GAIN_R, ctrl->val, &ret);
		cci_write(imx400->regmap, IMX400_REG_DIG_GAIN_B, ctrl->val, &ret);
		cci_write(imx400->regmap, IMX400_REG_DIG_GAIN_GB, ctrl->val, &ret);
		cci_write(imx400->regmap, IMX400_REG_GROUP_HOLD, 0, &ret);
		break;
	case V4L2_CID_VBLANK:
		cci_write(imx400->regmap, IMX400_REG_FLL, format->height + ctrl->val, &ret);
		break;
	case V4L2_CID_HBLANK:	/* lecture seule : fixé par le mode */
		break;
	default:
		ret = -EINVAL;
		break;
	}

	pm_runtime_put(&client->dev);
	return ret;
}

static const struct v4l2_ctrl_ops imx400_ctrl_ops = {
	.s_ctrl = imx400_set_ctrl,
};

static int imx400_init_controls(struct imx400 *imx400)
{
	struct i2c_client *client = v4l2_get_subdevdata(&imx400->sd);
	const struct imx400_mode *mode = &imx400->modes[0];
	struct v4l2_ctrl_handler *hdl = &imx400->ctrl_handler;
	struct v4l2_fwnode_device_properties props;
	int exposure_max, ret;

	ret = v4l2_ctrl_handler_init(hdl, 10);
	if (ret)
		return ret;

	imx400->pixel_rate = v4l2_ctrl_new_std(hdl, &imx400_ctrl_ops, V4L2_CID_PIXEL_RATE,
					       mode->pixel_rate, mode->pixel_rate, 1,
					       mode->pixel_rate);

	imx400->link_freq_menu[0] = mode->link_freq;
	imx400->link_freq = v4l2_ctrl_new_int_menu(hdl, &imx400_ctrl_ops, V4L2_CID_LINK_FREQ,
						   0, 0, imx400->link_freq_menu);
	if (imx400->link_freq)
		imx400->link_freq->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	imx400->vblank = v4l2_ctrl_new_std(hdl, &imx400_ctrl_ops, V4L2_CID_VBLANK,
					   mode->fll - mode->height,
					   IMX400_FLL_MAX - mode->height, 1,
					   mode->fll_def - mode->height);
	imx400->hblank = v4l2_ctrl_new_std(hdl, &imx400_ctrl_ops, V4L2_CID_HBLANK,
					   mode->llp - mode->width, mode->llp - mode->width,
					   1, mode->llp - mode->width);
	if (imx400->hblank)
		imx400->hblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	exposure_max = mode->fll_def - IMX400_EXPOSURE_OFFSET;
	imx400->exposure = v4l2_ctrl_new_std(hdl, &imx400_ctrl_ops, V4L2_CID_EXPOSURE,
					     IMX400_EXPOSURE_MIN, exposure_max, 1,
					     exposure_max / 2);
	v4l2_ctrl_new_std(hdl, &imx400_ctrl_ops, V4L2_CID_ANALOGUE_GAIN,
			  gain_codes ? 0 : 1, gain_codes ? IMX400_ANA_GAIN_MAX : 16, 1,
			  gain_codes ? 0 : 1);
	v4l2_ctrl_new_std(hdl, &imx400_ctrl_ops, V4L2_CID_DIGITAL_GAIN,
			  IMX400_DGTL_GAIN_MIN, IMX400_DGTL_GAIN_MAX, 1,
			  IMX400_DGTL_GAIN_DEFAULT);

	if (hdl->error) {
		ret = hdl->error;
		dev_err_probe(&client->dev, ret, "contrôles\n");
		goto erreur;
	}

	ret = v4l2_fwnode_device_parse(&client->dev, &props);
	if (ret)
		goto erreur;
	ret = v4l2_ctrl_new_fwnode_properties(hdl, &imx400_ctrl_ops, &props);
	if (ret)
		goto erreur;

	imx400->sd.ctrl_handler = hdl;
	return 0;

erreur:
	v4l2_ctrl_handler_free(hdl);
	return ret;
}

/* -----------------------------------------------------------------------------
 * Sous-périphérique
 */

static int imx400_enable_streams(struct v4l2_subdev *sd, struct v4l2_subdev_state *state,
				 u32 pad, u64 streams_mask)
{
	struct imx400 *imx400 = to_imx400(sd);
	struct i2c_client *client = v4l2_get_subdevdata(sd);
	const struct imx400_mode *mode;
	int ret;

	mode = imx400_mode_of(imx400, v4l2_subdev_state_get_format(state, 0));

	ret = pm_runtime_resume_and_get(&client->dev);
	if (ret < 0)
		return ret;

	if (!imx400->init_done) {
		ret = imx400_ecrire_bloc(imx400, &imx400->init);
		if (ret)
			goto erreur;
		imx400->init_done = true;
		usleep_range(10000, 11000);	/* Sony : ~10 ms avant le premier mode */
	}

	ret = imx400_ecrire_bloc(imx400, mode);
	if (ret)
		goto erreur;

	/* Image brute : pas de balance des blancs dans le capteur. */
	cci_write(imx400->regmap, IMX400_REG_WB_GR, 0x100, &ret);
	cci_write(imx400->regmap, IMX400_REG_WB_R, 0x100, &ret);
	cci_write(imx400->regmap, IMX400_REG_WB_B, 0x100, &ret);
	cci_write(imx400->regmap, IMX400_REG_WB_GB, 0x100, &ret);
	if (ret)
		goto erreur;

	ret = __v4l2_ctrl_handler_setup(imx400->sd.ctrl_handler);
	if (ret)
		goto erreur;

	ret = cci_write(imx400->regmap, IMX400_REG_MODE_SELECT, 1, NULL);
	if (ret)
		goto erreur;

	dev_info(&client->dev, "flux %s démarré\n", mode->name);
	return 0;

erreur:
	dev_err(&client->dev, "démarrage du flux %s : %d\n", mode->name, ret);
	pm_runtime_put_autosuspend(&client->dev);
	return ret;
}

static int imx400_disable_streams(struct v4l2_subdev *sd, struct v4l2_subdev_state *state,
				  u32 pad, u64 streams_mask)
{
	struct imx400 *imx400 = to_imx400(sd);
	struct i2c_client *client = v4l2_get_subdevdata(sd);
	int ret;

	ret = cci_write(imx400->regmap, IMX400_REG_MODE_SELECT, 0, NULL);
	pm_runtime_put_autosuspend(&client->dev);
	return ret;
}

static int imx400_enum_mbus_code(struct v4l2_subdev *sd, struct v4l2_subdev_state *state,
				 struct v4l2_subdev_mbus_code_enum *code)
{
	if (code->index)
		return -EINVAL;
	code->code = MEDIA_BUS_FMT_SRGGB10_1X10;
	return 0;
}

static int imx400_enum_frame_size(struct v4l2_subdev *sd, struct v4l2_subdev_state *state,
				  struct v4l2_subdev_frame_size_enum *fse)
{
	struct imx400 *imx400 = to_imx400(sd);

	if (fse->index >= imx400->num_modes || fse->code != MEDIA_BUS_FMT_SRGGB10_1X10)
		return -EINVAL;
	fse->min_width = fse->max_width = imx400->modes[fse->index].width;
	fse->min_height = fse->max_height = imx400->modes[fse->index].height;
	return 0;
}

static int imx400_set_pad_format(struct v4l2_subdev *sd, struct v4l2_subdev_state *state,
				 struct v4l2_subdev_format *fmt)
{
	struct imx400 *imx400 = to_imx400(sd);
	const struct imx400_mode *mode;
	struct v4l2_mbus_framefmt *format;
	int ret;

	mode = v4l2_find_nearest_size(imx400->modes, imx400->num_modes, width, height,
				      fmt->format.width, fmt->format.height);

	fmt->format.code = MEDIA_BUS_FMT_SRGGB10_1X10;
	fmt->format.width = mode->width;
	fmt->format.height = mode->height;
	fmt->format.field = V4L2_FIELD_NONE;
	fmt->format.colorspace = V4L2_COLORSPACE_RAW;
	fmt->format.ycbcr_enc = V4L2_YCBCR_ENC_601;
	fmt->format.quantization = V4L2_QUANTIZATION_FULL_RANGE;
	fmt->format.xfer_func = V4L2_XFER_FUNC_NONE;

	format = v4l2_subdev_state_get_format(state, 0);
	*format = fmt->format;
	*v4l2_subdev_state_get_crop(state, 0) = mode->crop;

	if (fmt->which == V4L2_SUBDEV_FORMAT_ACTIVE && imx400->vblank) {
		int exposure_max = mode->fll_def - IMX400_EXPOSURE_OFFSET;

		ret = __v4l2_ctrl_modify_range(imx400->vblank, mode->fll - mode->height,
					       IMX400_FLL_MAX - mode->height, 1,
					       mode->fll_def - mode->height);
		if (!ret)
			ret = __v4l2_ctrl_s_ctrl(imx400->vblank, mode->fll_def - mode->height);
		if (!ret)
			ret = __v4l2_ctrl_modify_range(imx400->exposure, IMX400_EXPOSURE_MIN,
						       exposure_max, 1, exposure_max / 2);
		if (!ret)
			ret = __v4l2_ctrl_modify_range(imx400->hblank, mode->llp - mode->width,
						       mode->llp - mode->width, 1,
						       mode->llp - mode->width);
		if (!ret)
			ret = __v4l2_ctrl_modify_range(imx400->pixel_rate, mode->pixel_rate,
						       mode->pixel_rate, 1, mode->pixel_rate);
		if (ret)
			return ret;
	}
	return 0;
}

static int imx400_get_selection(struct v4l2_subdev *sd, struct v4l2_subdev_state *state,
				struct v4l2_subdev_selection *sel)
{
	switch (sel->target) {
	case V4L2_SEL_TGT_CROP:
		sel->r = *v4l2_subdev_state_get_crop(state, 0);
		return 0;
	case V4L2_SEL_TGT_NATIVE_SIZE:
	case V4L2_SEL_TGT_CROP_DEFAULT:
	case V4L2_SEL_TGT_CROP_BOUNDS:
		sel->r.top = 0;
		sel->r.left = 0;
		sel->r.width = IMX400_NATIVE_WIDTH;
		sel->r.height = IMX400_NATIVE_HEIGHT;
		return 0;
	}
	return -EINVAL;
}

static int imx400_init_state(struct v4l2_subdev *sd, struct v4l2_subdev_state *state)
{
	struct imx400 *imx400 = to_imx400(sd);
	struct v4l2_subdev_format fmt = {
		.which = V4L2_SUBDEV_FORMAT_TRY,
		.pad = 0,
		.format = {
			.code = MEDIA_BUS_FMT_SRGGB10_1X10,
			.width = imx400->modes[0].width,
			.height = imx400->modes[0].height,
		},
	};

	return imx400_set_pad_format(sd, state, &fmt);
}

static const struct v4l2_subdev_video_ops imx400_video_ops = {
	.s_stream = v4l2_subdev_s_stream_helper,
};

static const struct v4l2_subdev_pad_ops imx400_pad_ops = {
	.enum_mbus_code = imx400_enum_mbus_code,
	.get_fmt = v4l2_subdev_get_fmt,
	.set_fmt = imx400_set_pad_format,
	.get_selection = imx400_get_selection,
	.enum_frame_size = imx400_enum_frame_size,
	.enable_streams = imx400_enable_streams,
	.disable_streams = imx400_disable_streams,
};

static const struct v4l2_subdev_ops imx400_subdev_ops = {
	.video = &imx400_video_ops,
	.pad = &imx400_pad_ops,
};

static const struct v4l2_subdev_internal_ops imx400_internal_ops = {
	.init_state = imx400_init_state,
};

/* -----------------------------------------------------------------------------
 * Alimentation (séquence de Sony : vana, vio, vaf, horloge, puis sortie du reset)
 */

static int imx400_power_on(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct imx400 *imx400 = to_imx400(sd);
	int ret;

	ret = regulator_bulk_enable(IMX400_NUM_SUPPLIES, imx400->supplies);
	if (ret) {
		dev_err(dev, "alimentations : %d\n", ret);
		return ret;
	}
	usleep_range(3000, 4000);

	ret = clk_prepare_enable(imx400->xclk);
	if (ret) {
		dev_err(dev, "horloge : %d\n", ret);
		regulator_bulk_disable(IMX400_NUM_SUPPLIES, imx400->supplies);
		return ret;
	}
	usleep_range(1000, 2000);

	gpiod_set_value_cansleep(imx400->reset_gpio, 0);
	msleep(10);
	return 0;
}

static int imx400_power_off(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct imx400 *imx400 = to_imx400(sd);

	gpiod_set_value_cansleep(imx400->reset_gpio, 1);
	clk_disable_unprepare(imx400->xclk);
	regulator_bulk_disable(IMX400_NUM_SUPPLIES, imx400->supplies);
	imx400->init_done = false;
	return 0;
}

/* -----------------------------------------------------------------------------
 * Sonde
 */

static int imx400_check_hwcfg(struct device *dev, struct imx400 *imx400)
{
	struct fwnode_handle *endpoint;
	struct v4l2_fwnode_endpoint ep = { .bus_type = V4L2_MBUS_CSI2_DPHY };
	unsigned long bitmap;
	int ret;

	endpoint = fwnode_graph_get_next_endpoint(dev_fwnode(dev), NULL);
	if (!endpoint)
		return dev_err_probe(dev, -EINVAL, "pas de point de connexion (endpoint)\n");

	ret = v4l2_fwnode_endpoint_alloc_parse(endpoint, &ep);
	fwnode_handle_put(endpoint);
	if (ret)
		return dev_err_probe(dev, ret, "point de connexion illisible\n");

	if (ep.bus.mipi_csi2.num_data_lanes != 4) {
		ret = dev_err_probe(dev, -EINVAL, "4 voies CSI-2 attendues\n");
		goto fin;
	}

	ret = v4l2_link_freq_to_bitmap(dev, ep.link_frequencies, ep.nr_of_link_frequencies,
				       imx400->link_freq_menu, 1, &bitmap);
	if (ret)
		dev_err_probe(dev, ret, "link-frequencies doit contenir %lld\n",
			      imx400->link_freq_menu[0]);
fin:
	v4l2_fwnode_endpoint_free(&ep);
	return ret;
}

static int imx400_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	const struct i2c_adapter_quirks *q = client->adapter->quirks;
	const char *fw_name = IMX400_FIRMWARE_DEFAUT;
	struct imx400 *imx400;
	unsigned int i;
	u64 id;
	int ret;

	imx400 = devm_kzalloc(dev, sizeof(*imx400), GFP_KERNEL);
	if (!imx400)
		return -ENOMEM;

	v4l2_i2c_subdev_init(&imx400->sd, client, &imx400_subdev_ops);
	imx400->sd.internal_ops = &imx400_internal_ops;

	imx400->max_chunk = 32;
	if (q && q->max_write_len > 2)
		imx400->max_chunk = min_t(unsigned int, q->max_write_len - 2, 255);

	device_property_read_string(dev, "firmware-name", &fw_name);
	ret = imx400_charger_sequences(imx400, fw_name);
	if (ret)
		return ret;
	imx400->link_freq_menu[0] = imx400->modes[0].link_freq;

	ret = imx400_check_hwcfg(dev, imx400);
	if (ret)
		return ret;

	imx400->regmap = devm_cci_regmap_init_i2c(client, 16);
	if (IS_ERR(imx400->regmap))
		return dev_err_probe(dev, PTR_ERR(imx400->regmap), "regmap CCI\n");

	imx400->xclk = devm_clk_get(dev, NULL);
	if (IS_ERR(imx400->xclk))
		return dev_err_probe(dev, PTR_ERR(imx400->xclk), "horloge absente\n");
	imx400->xclk_freq = clk_get_rate(imx400->xclk);
	if (!imx400->xclk_freq || imx400->xclk_freq % IMX400_XCLK_SEQUENCES ||
	    imx400->xclk_freq / IMX400_XCLK_SEQUENCES > 4)
		return dev_err_probe(dev, -EINVAL,
				     "horloge de %u Hz : multiple de 8 MHz attendu (8, 16, 24 MHz)\n",
				     imx400->xclk_freq);

	for (i = 0; i < IMX400_NUM_SUPPLIES; i++)
		imx400->supplies[i].supply = imx400_supply_name[i];
	ret = devm_regulator_bulk_get(dev, IMX400_NUM_SUPPLIES, imx400->supplies);
	if (ret)
		return dev_err_probe(dev, ret, "alimentations\n");

	imx400->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(imx400->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(imx400->reset_gpio), "reset-gpios\n");

	ret = imx400_power_on(dev);
	if (ret)
		return ret;

	ret = cci_read(imx400->regmap, IMX400_REG_ID, &id, NULL);
	if (ret) {
		dev_err_probe(dev, ret, "le capteur ne répond pas en I2C\n");
		goto erreur_alim;
	}
	dev_info(dev, "IMX400 détecté (0x0016 = 0x%04llx), %u mode(s), horloge %u Hz, paquets I2C de %u octets\n",
		 id, imx400->num_modes, imx400->xclk_freq, imx400->max_chunk);

	ret = imx400_init_controls(imx400);
	if (ret)
		goto erreur_alim;

	imx400->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	imx400->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;
	imx400->pad.flags = MEDIA_PAD_FL_SOURCE;
	ret = media_entity_pads_init(&imx400->sd.entity, 1, &imx400->pad);
	if (ret)
		goto erreur_ctrl;

	imx400->sd.state_lock = imx400->ctrl_handler.lock;
	ret = v4l2_subdev_init_finalize(&imx400->sd);
	if (ret)
		goto erreur_entite;

	pm_runtime_set_active(dev);
	pm_runtime_enable(dev);

	ret = v4l2_async_register_subdev_sensor(&imx400->sd);
	if (ret)
		goto erreur_subdev;

	pm_runtime_idle(dev);
	pm_runtime_set_autosuspend_delay(dev, 1000);
	pm_runtime_use_autosuspend(dev);
	return 0;

erreur_subdev:
	v4l2_subdev_cleanup(&imx400->sd);
	pm_runtime_disable(dev);
	pm_runtime_set_suspended(dev);
erreur_entite:
	media_entity_cleanup(&imx400->sd.entity);
erreur_ctrl:
	v4l2_ctrl_handler_free(&imx400->ctrl_handler);
erreur_alim:
	imx400_power_off(dev);
	return ret;
}

static void imx400_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct imx400 *imx400 = to_imx400(sd);

	v4l2_async_unregister_subdev(sd);
	v4l2_subdev_cleanup(sd);
	media_entity_cleanup(&sd->entity);
	v4l2_ctrl_handler_free(&imx400->ctrl_handler);

	pm_runtime_disable(&client->dev);
	if (!pm_runtime_status_suspended(&client->dev)) {
		imx400_power_off(&client->dev);
		pm_runtime_set_suspended(&client->dev);
	}
}

static const struct of_device_id imx400_dt_ids[] = {
	{ .compatible = "sony,imx400" },
	{ }
};
MODULE_DEVICE_TABLE(of, imx400_dt_ids);

static const struct dev_pm_ops imx400_pm_ops = {
	SET_RUNTIME_PM_OPS(imx400_power_off, imx400_power_on, NULL)
};

static struct i2c_driver imx400_i2c_driver = {
	.driver = {
		.name = "imx400",
		.of_match_table = imx400_dt_ids,
		.pm = &imx400_pm_ops,
	},
	.probe = imx400_probe,
	.remove = imx400_remove,
};
module_i2c_driver(imx400_i2c_driver);

MODULE_FIRMWARE(IMX400_FIRMWARE_DEFAUT);
MODULE_DESCRIPTION("Sony IMX400 (Xperia XZ3), séquences lues dans un fichier");
MODULE_LICENSE("GPL");
