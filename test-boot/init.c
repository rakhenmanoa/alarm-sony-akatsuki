/*
 * init.c — init minimal pour tester le démarrage du noyau pmOS sur le Xperia XZ3.
 *
 * Aucune bibliothèque (ni libc, ni busybox) : appels système Linux aarch64 directs.
 * Compilé par test-boot/build.sh (clang --target=aarch64-linux-gnu -nostdlib -static).
 *
 * Ce qu'il fait :
 *   1. monte /dev, /proc, /sys et configfs ;
 *   2. charge les modules du gadget USB (libcomposite, u_serial, usb_f_acm,
 *      u_ether, usb_f_ncm), copiés tels quels (.ko.zst) depuis le paquet pmOS ;
 *   3. présente le téléphone au PC comme port série (ACM → /dev/ttyACM0 sur le PC)
 *      + carte réseau (NCM, téléphone en 172.16.42.1) ;
 *   4. sur le port série : envoie les messages du noyau au fil de l'eau ;
 *      Entrée = renvoyer tout le journal depuis le début,
 *      « b » + Entrée = redémarrer en fastboot, « r » = redémarrer, « p » = éteindre.
 *
 * Si le gadget USB ne peut pas être créé, l'init redémarre le téléphone au bout
 * de 15 s : un redémarrage seul signifie donc « le noyau a démarré et lancé init,
 * mais l'USB ne fonctionne pas ». Aucun accès à l'UFS ni à la carte SD.
 */

typedef unsigned long u64;
typedef long s64;
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;

/* ----------------------------------------------------- appels système aarch64 */
#define SYS_ioctl 29
#define SYS_mkdirat 34
#define SYS_symlinkat 36
#define SYS_mount 40
#define SYS_openat 56
#define SYS_close 57
#define SYS_getdents64 61
#define SYS_lseek 62
#define SYS_read 63
#define SYS_write 64
#define SYS_ppoll 73
#define SYS_nanosleep 101
#define SYS_reboot 142
#define SYS_socket 198
#define SYS_finit_module 273

#define AT_FDCWD (-100)
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_NOCTTY 0400
#define O_NONBLOCK 04000
#define O_DIRECTORY 040000
#define O_CLOEXEC 02000000
#define EAGAIN 11
#define EINTR 4
#define EPIPE 32

static long sc6(long n, long a, long b, long c, long d, long e, long f)
{
	register long x8 __asm__("x8") = n;
	register long x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b;
	register long x2 __asm__("x2") = c;
	register long x3 __asm__("x3") = d;
	register long x4 __asm__("x4") = e;
	register long x5 __asm__("x5") = f;
	__asm__ volatile("svc #0"
			 : "+r"(x0)
			 : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5)
			 : "memory", "cc");
	return x0;
}
#define sc(n, a, b, c) sc6(n, (long)(a), (long)(b), (long)(c), 0, 0, 0)

/* clang peut générer des appels à memset/memcpy même en mode autonome */
void *memset(void *d, int c, unsigned long n)
{
	u8 *p = d;
	while (n--)
		*p++ = (u8)c;
	return d;
}
void *memcpy(void *d, const void *s, unsigned long n)
{
	u8 *p = d;
	const u8 *q = s;
	while (n--)
		*p++ = *q++;
	return d;
}

static unsigned long slen(const char *s)
{
	unsigned long n = 0;
	while (s[n])
		n++;
	return n;
}

static void sleep_ms(long ms)
{
	long ts[2] = { ms / 1000, (ms % 1000) * 1000000L };
	sc(SYS_nanosleep, ts, 0, 0);
}

/* ------------------------------------------------------------------ journal */
static int kmsg = -1;

static char *put_s(char *p, const char *s)
{
	while (*s)
		*p++ = *s++;
	return p;
}
static char *put_d(char *p, long v)
{
	char t[24];
	int i = 0;
	if (v < 0) {
		*p++ = '-';
		v = -v;
	}
	do
		t[i++] = (char)('0' + v % 10);
	while ((v /= 10) && i < 23);
	while (i)
		*p++ = t[--i];
	return p;
}

/* log("texte", code) : écrit dans le journal du noyau (visible à l'écran et en dmesg) */
static void logc(const char *msg, long code, int with_code)
{
	char b[256], *p = b;
	p = put_s(p, "akatsuki-test: ");
	p = put_s(p, msg);
	if (with_code) {
		p = put_s(p, " (");
		p = put_d(p, code);
		p = put_s(p, ")");
	}
	*p++ = '\n';
	if (kmsg >= 0)
		sc(SYS_write, kmsg, b, p - b);
}
#define log(m) logc(m, 0, 0)
#define logr(m, r) logc(m, r, 1)

/* --------------------------------------------------------------- fichiers */
static long xopen(const char *path, long flags)
{
	return sc6(SYS_openat, AT_FDCWD, (long)path, flags | O_CLOEXEC, 0, 0, 0);
}

static void xmkdir(const char *path)
{
	sc(SYS_mkdirat, AT_FDCWD, path, 0755);
}

static long write_file(const char *path, const char *val)
{
	long fd = xopen(path, O_WRONLY);
	long r;
	if (fd < 0) {
		logr(path, fd);
		return fd;
	}
	r = sc(SYS_write, fd, val, slen(val));
	sc(SYS_close, fd, 0, 0);
	if (r < 0)
		logr(path, r);
	return r < 0 ? r : 0;
}

static long xmount(const char *src, const char *dst, const char *type)
{
	xmkdir(dst);
	return sc6(SYS_mount, (long)src, (long)dst, (long)type, 0, 0, 0);
}

static long load_module(const char *path)
{
	long fd = xopen(path, O_RDONLY), r;
	if (fd < 0) {
		logr(path, fd);
		return fd;
	}
	/* .ko.zst : le noyau décompresse lui-même (CONFIG_MODULE_DECOMPRESS=y) */
	r = sc(SYS_finit_module, fd, "", 4 /* MODULE_INIT_COMPRESSED_FILE */);
	sc(SYS_close, fd, 0, 0);
	if (r < 0 && r != -17 /* EEXIST : déjà chargé */)
		logr(path, r);
	else
		log(path);
	return r;
}

/* Premier nom dans /sys/class/udc (ex. « a600000.usb »), 0 si absent */
static int first_udc(char *out, int max)
{
	char buf[1024];
	long fd = xopen("/sys/class/udc", O_RDONLY | O_DIRECTORY), n, i;
	int ok = 0;
	if (fd < 0)
		return 0;
	while (!ok && (n = sc(SYS_getdents64, fd, buf, sizeof buf)) > 0) {
		for (i = 0; i < n;) {
			u16 reclen = *(u16 *)(buf + i + 16);
			char *name = buf + i + 19;
			if (name[0] != '.') {
				int k = 0;
				while (name[k] && k < max - 1) {
					out[k] = name[k];
					k++;
				}
				out[k] = 0;
				ok = 1;
				break;
			}
			i += reclen;
		}
	}
	sc(SYS_close, fd, 0, 0);
	return ok;
}

/* ------------------------------------------------------------- gadget USB */
#define G "/sys/kernel/config/usb_gadget/akatsuki"

static int setup_gadget(void)
{
	char udc[64];
	int i;

	xmkdir(G);
	write_file(G "/idVendor", "0x18d1");
	write_file(G "/idProduct", "0xd001");
	/* composite série + réseau : classe « Miscellaneous / IAD » */
	write_file(G "/bDeviceClass", "0xEF");
	write_file(G "/bDeviceSubClass", "0x02");
	write_file(G "/bDeviceProtocol", "0x01");
	xmkdir(G "/strings/0x409");
	write_file(G "/strings/0x409/manufacturer", "Sony");
	write_file(G "/strings/0x409/product", "Xperia XZ3 test noyau");
	write_file(G "/strings/0x409/serialnumber", "akatsuki-test");
	xmkdir(G "/configs/c.1");
	xmkdir(G "/configs/c.1/strings/0x409");
	write_file(G "/configs/c.1/strings/0x409/configuration", "ACM+NCM");

	xmkdir(G "/functions/acm.GS0");
	xmkdir(G "/functions/ncm.usb0");
	sc(SYS_symlinkat, G "/functions/acm.GS0", AT_FDCWD, G "/configs/c.1/acm.GS0");
	sc(SYS_symlinkat, G "/functions/ncm.usb0", AT_FDCWD, G "/configs/c.1/ncm.usb0");

	/* Le contrôleur dwc3 peut apparaître tard (sondage différé) : attendre 60 s */
	for (i = 0; i < 120; i++) {
		if (first_udc(udc, sizeof udc))
			break;
		sleep_ms(500);
	}
	if (i == 120) {
		log("ERREUR : aucun contrôleur USB device dans /sys/class/udc");
		return -1;
	}
	log(udc);
	return write_file(G "/UDC", udc);
}

/* ------------------------------------------------- réseau : usb0 172.16.42.1 */
#define SIOCGIFFLAGS 0x8913
#define SIOCSIFFLAGS 0x8914
#define SIOCSIFADDR 0x8916
#define SIOCSIFNETMASK 0x891c

struct ifreq {
	char name[16];
	union {
		struct {
			u16 family;
			u16 port;
			u32 addr;
			u8 zero[8];
		} sin;
		short flags;
		u8 pad[24];
	} u;
};

static void setup_net(void)
{
	struct ifreq r;
	long s = sc(SYS_socket, 2 /* AF_INET */, 2 /* SOCK_DGRAM */, 0), e;

	if (s < 0) {
		logr("socket", s);
		return;
	}
	memset(&r, 0, sizeof r);
	memcpy(r.name, "usb0", 5);
	r.u.sin.family = 2;
	r.u.sin.addr = 172 | 16 << 8 | 42 << 16 | 1u << 24; /* 172.16.42.1 */
	if ((e = sc(SYS_ioctl, s, SIOCSIFADDR, &r)) < 0)
		logr("SIOCSIFADDR usb0", e);
	r.u.sin.addr = 255 | 255 << 8 | 255 << 16; /* 255.255.255.0 */
	if ((e = sc(SYS_ioctl, s, SIOCSIFNETMASK, &r)) < 0)
		logr("SIOCSIFNETMASK usb0", e);
	memset(&r.u, 0, sizeof r.u);
	sc(SYS_ioctl, s, SIOCGIFFLAGS, &r);
	r.u.flags |= 1; /* IFF_UP */
	if ((e = sc(SYS_ioctl, s, SIOCSIFFLAGS, &r)) < 0)
		logr("SIOCSIFFLAGS usb0", e);
	else
		log("usb0 = 172.16.42.1/24");
	sc(SYS_close, s, 0, 0);
}

/* --------------------------------------------------------------- arrêt */
static void do_reboot(long cmd, const char *arg)
{
	log("redémarrage demandé");
	sleep_ms(300);
	sc6(SYS_reboot, 0xfee1dead, 672274793, cmd, (long)arg, 0, 0);
}
#define RB_RESTART 0x01234567
#define RB_RESTART2 0xA1B2C3D4
#define RB_POWER_OFF 0x4321FEDC

/* ------------------------------------------------ port série : journal */
static long tty = -1;

static void tty_write(const char *b, long n)
{
	int tries = 0;
	while (n > 0 && tty >= 0) {
		long r = sc(SYS_write, tty, b, n);
		if (r > 0) {
			b += r;
			n -= r;
			tries = 0;
		} else if ((r == -EAGAIN || r == -EINTR) && tries++ < 200) {
			sleep_ms(10);
		} else {
			return; /* PC déconnecté : on abandonne cette ligne */
		}
	}
}

/* Un enregistrement /dev/kmsg « prio,seq,µs,drapeaux;message\n » → « [s.µs] message\n » */
static void forward_record(const char *rec, long n)
{
	char out[1200], *p = out;
	long i = 0, field = 0, us = 0;
	while (i < n && rec[i] != ';') {
		if (rec[i] == ',')
			field++;
		else if (field == 2 && rec[i] >= '0' && rec[i] <= '9')
			us = us * 10 + (rec[i] - '0');
		i++;
	}
	if (i >= n)
		return;
	i++;
	*p++ = '[';
	p = put_d(p, us / 1000000);
	*p++ = '.';
	{
		long f = us % 1000000, d = 100000;
		while (d) {
			*p++ = (char)('0' + f / d % 10);
			d /= 10;
		}
	}
	*p++ = ']';
	*p++ = ' ';
	while (i < n && rec[i] != '\n' && p < out + sizeof out - 2)
		*p++ = rec[i++];
	*p++ = '\n';
	tty_write(out, p - out);
}

static void dump_all(void)
{
	char rec[1100];
	long fd = xopen("/dev/kmsg", O_RDONLY | O_NONBLOCK), n;
	if (fd < 0)
		return;
	for (;;) {
		n = sc(SYS_read, fd, rec, sizeof rec);
		if (n == -EPIPE)
			continue;
		if (n <= 0)
			break;
		forward_record(rec, n);
	}
	sc(SYS_close, fd, 0, 0);
}

static const char help[] =
	"\n=== Xperia XZ3 : le noyau a demarre ===\n"
	"Entree : tout le journal | b : fastboot | r : redemarrer | p : eteindre\n\n";

struct pollfd {
	int fd;
	short events, revents;
};

static void serial_loop(void)
{
	char rec[1100], in[64];
	long follow = xopen("/dev/kmsg", O_RDONLY | O_NONBLOCK), n, i;

	if (follow >= 0)
		sc(SYS_lseek, follow, 0, 2 /* SEEK_END : seulement les nouveaux */);

	for (;;) {
		struct pollfd p[2];
		if (tty < 0) {
			tty = xopen("/dev/ttyGS0", O_RDWR | O_NOCTTY | O_NONBLOCK);
			if (tty < 0) {
				sleep_ms(1000);
				continue;
			}
		}
		p[0].fd = (int)tty;
		p[0].events = 1; /* POLLIN */
		p[0].revents = 0;
		p[1].fd = (int)follow;
		p[1].events = 1;
		p[1].revents = 0;
		if (sc6(SYS_ppoll, (long)p, 2, 0, 0, 8, 0) < 0) {
			sleep_ms(100);
			continue;
		}
		if (p[1].revents & 1) {
			n = sc(SYS_read, follow, rec, sizeof rec);
			if (n > 0)
				forward_record(rec, n);
		}
		if (p[0].revents & 1) {
			n = sc(SYS_read, tty, in, sizeof in);
			for (i = 0; i < n; i++) {
				if (in[i] == 'b')
					do_reboot(RB_RESTART2, "bootloader");
				else if (in[i] == 'r')
					do_reboot(RB_RESTART, 0);
				else if (in[i] == 'p')
					do_reboot(RB_POWER_OFF, 0);
			}
			if (n > 0) {
				tty_write(help, sizeof help - 1);
				dump_all();
			} else if (n == 0) {
				sc(SYS_close, tty, 0, 0); /* PC parti : rouvrir */
				tty = -1;
				sleep_ms(500);
			}
		}
		if (p[0].revents & (8 | 16) /* POLLERR | POLLHUP */) {
			sc(SYS_close, tty, 0, 0);
			tty = -1;
			sleep_ms(500);
		}
	}
}

/* ------------------------------------------------------------------ main */
static const char *const modules[] = {
	"/lib/modules/libcomposite.ko.zst", "/lib/modules/u_serial.ko.zst",
	"/lib/modules/usb_f_acm.ko.zst",    "/lib/modules/u_ether.ko.zst",
	"/lib/modules/usb_f_ncm.ko.zst",
};

static void run(void)
{
	unsigned int i;

	xmount("devtmpfs", "/dev", "devtmpfs");
	xmount("proc", "/proc", "proc");
	xmount("sysfs", "/sys", "sysfs");
	kmsg = xopen("/dev/kmsg", O_WRONLY);
	log("============================================");
	log("init lancé : le noyau a démarré !");
	log("============================================");
	xmount("configfs", "/sys/kernel/config", "configfs");

	for (i = 0; i < sizeof modules / sizeof modules[0]; i++)
		load_module(modules[i]);

	if (setup_gadget() < 0) {
		log("gadget USB impossible : redémarrage dans 15 s");
		sleep_ms(15000);
		do_reboot(RB_RESTART, 0);
	}
	sleep_ms(500);
	setup_net();
	log("USB prêt : sur le PC, « cat /dev/ttyACM0 » ou ping 172.16.42.1");
	serial_loop();
}

__attribute__((noreturn)) void cmain(void)
{
	run();
	for (;;)
		sleep_ms(1000000);
}

__asm__(".globl _start\n"
	"_start:\n"
	"  mov x29, #0\n"
	"  mov x30, #0\n"
	"  bl cmain\n" /* la pile est déjà alignée sur 16 octets à l'entrée */
	"  b .\n");
