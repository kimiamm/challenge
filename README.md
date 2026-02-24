# مستندات پروژه ip2loc.ir

این مستندات، مراحل کامل راه‌اندازی زیرساخت ابری، وب‌سرور، مانیتورینگ و دیپلوی اپلیکیشن را به‌صورت گام‌به‌گام توضیح می‌دهد.

---

## فهرست مطالب

1. [ساخت سرورهای ابری](#۱-ساخت-سرورهای-ابری)
2. [راه‌اندازی شبکه خصوصی و NFS](#۲-راه‌اندازی-شبکه-خصوصی-و-nfs)
3. [نصب و پیکربندی Nginx و PHP-FPM](#۳-نصب-و-پیکربندی-nginx-و-php-fpm)
4. [دریافت گواهی SSL با Certbot](#۴-دریافت-گواهی-ssl-با-certbot)
5. [پیکربندی Nginx برای دامنه](#۵-پیکربندی-nginx-برای-دامنه)
6. [مانیتورینگ با Node Exporter، Prometheus و Grafana](#۶-مانیتورینگ)
7. [پیکربندی فایروال](#۷-پیکربندی-فایروال)
8. [داکرایز کردن پروژه Next.js](#۸-داکرایز-کردن-پروژه-nextjs)
9. [Container Registry و دیپلوی روی CaaS](#۹-container-registry-و-دیپلوی-روی-caas)

---

## معماری کلی زیرساخت

```
                                   [ کاربر ]
                                       |
                                    HTTPS
                                       |
                             +---------v----------+
                             |   CDN آروان‌كلاد    |
                             +--+------+-------+--+
                                |      |       |
                   Load Balance |      | Load  | ارسال لاگ
                                |      | Balance|
                                |      |       |
              +-----------------+      +---+   +------------------+
              |                            |                      |
              v                            v                      v
+----------------------------+  +----------------------------+  +-----------------------+
|         Server 1           |  |         Server 2           |  |       ELK Stack        |
|   Nginx + PHP-FPM          |  |   Nginx + PHP-FPM          |  |  Elasticsearch        |
|   Node Exporter :9100      |  |   Node Exporter :9100      |  |  Logstash             |
+-----+------------+---------+  +----+------------+----------+  |  Kibana               |
      |            |                 |            |              +-----------+-----------+
      |  شبکه      |                 |  شبکه      |                          |
      |  خصوصی     |                 |  خصوصی     |                          | Backup
      v            v                 v            v                          v
+----------+  +---------+  +----------+  +---------+             +---------------------+
|   NFS    |  |  DBaaS  |  |   NFS    |  |  DBaaS  |             |   Object Storage    |
|   File   |  |  MySQL  |  |   File   |  |  MySQL  |             |  (بك‌آپ لاگ‌ها)      |
| Storage  |  |         |  | Storage  |  |         |             +---------------------+
+----------+  +---------+  +----------+  +---------+


 +------------------------------------------------------------------+
 |                     CaaS آروان‌كلاد                               |
 |                                                                  |
 |   +------------------+        +----------------------------+     |
 |   |   Blog App       |        |        Prometheus          |     |
 |   |   Next.js        |        |                            |     |
 |   |                  |        |  Scrape :9100 <-- Server 1 |     |
 |   +------------------+        |  Scrape :9100 <-- Server 2 |     |
 |          ^                    +-------------+--------------+     |
 |          |                                  |                    |
 |       HTTPS                              Query                   |
 |       از CDN                                |                    |
 |                                            v                    |
 |                                  +------------------+           |
 |                                  |     Grafana      |           |
 |                                  |    Dashboard     |           |
 |                                  +------------------+           |
 +------------------------------------------------------------------+
```

---

## ۱. ساخت سرورهای ابری

در ابتدا دو سرور ابری (Cloud Instance) در دیتاسنتر **شهریار** آروان‌کلاد ساخته شدند. این سرورها پایه‌ی کل زیرساخت پروژه هستند؛ یکی برای سرو وب‌سایت و دیگری برای سرویس‌های جانبی.

---

## ۲. راه‌اندازی شبکه خصوصی و NFS

### شبکه خصوصی چیست؟

شبکه خصوصی (Private Network) یک شبکه‌ی داخلی است که فقط سرورهای داخل آن می‌توانند با هم ارتباط برقرار کنند و از اینترنت عمومی قابل دسترسی نیست. این باعث می‌شود انتقال داده بین سرورها امن‌تر و سریع‌تر باشد.

- **ساب‌نت:** `192.168.1.0/24` یعنی آدرس‌های IP از `192.168.1.1` تا `192.168.1.254` در این شبکه قرار دارند.
- **DHCP:** پروتکلی که به‌صورت خودکار به هر سرور یک IP اختصاص می‌دهد، بدون اینکه نیاز باشد دستی تنظیم کنید.

### NFS چیست؟

NFS مخفف **Network File System** است. یک پروتکل است که به شما اجازه می‌دهد یک فولدر روی یک سرور را روی سرور دیگری **mount** کنید (یعنی به آن وصل شوید) و انگار که آن فولدر روی خود سرور دوم است باهاش کار کنید. مثل اینکه یک هارد اکسترنال را به چند کامپیوتر همزمان وصل کنید.

در اینجا یک **File Storage** از پنل آروان‌کلاد ساخته شد و از طریق NFS به سرورها متصل شد تا فایل‌های وردپرس روی آن ذخیره شوند.

### نصب کلاینت NFS

```bash
sudo apt-get install nfs-common
```

این دستور پکیج `nfs-common` را نصب می‌کند. این پکیج شامل ابزارهایی است که سرور لینوکس برای **وصل شدن** (mount کردن) به یک سرور NFS به آن نیاز دارد. بدون این پکیج، سیستم‌عامل نمی‌داند چطور با پروتکل NFS ارتباط برقرار کند.

### ساخت فولدر mount

```bash
sudo mkdir /mnt/arvanfs
```

این دستور یک فولدر خالی به نام `arvanfs` در مسیر `/mnt` می‌سازد. `/mnt` در لینوکس معمولاً محلی است که دیوایس‌ها و فضاهای ذخیره‌سازی خارجی به آن متصل می‌شوند. این فولدر نقطه‌ی اتصال (mount point) ما خواهد بود.

### تغییر مالکیت فولدر

```bash
sudo chown -R www-data:www-data /mnt/arvanfs
```

- **`chown`**: مخفف **Change Ownership** است و مالک یک فایل یا فولدر را تغییر می‌دهد.
- **`-R`**: مخفف **Recursive** است؛ یعنی تغییر را روی فولدر و تمام محتویات داخلش اعمال کن.
- **`www-data:www-data`**: یوزر و گروه `www-data`. در اوبونتو، سرویس Nginx با این یوزر اجرا می‌شود. اگر Nginx با یوزر `www-data` کار کند اما مالک فولدر کس دیگری باشد، Nginx نمی‌تواند فایل‌ها را بخواند یا بنویسد.
- **`/mnt/arvanfs`**: مسیر فولدری که مالکیتش را تغییر می‌دهیم.

### Mount کردن فضای NFS

```bash
sudo mount -t nfs "192.168.1.3:/volumes/_nogroup/10416600-8423-4a3f-9afc-b07d8dfe38d2/b6cd7b74-2cfd-4f25-9072-7881887bed2e" /mnt/arvanfs
```

- **`mount`**: دستوری است که یک دیوایس یا فضای ذخیره‌سازی را به سیستم‌عامل متصل می‌کند.
- **`-t nfs`**: نوع فایل‌سیستم را مشخص می‌کند. اینجا به سیستم می‌گوییم این یک NFS است.
- **`"192.168.1.3:/volumes/..."`**: آدرس سرور NFS (IP داخلی شبکه خصوصی) و مسیر فولدر روی آن سرور. این مسیر طولانی، آدرس دقیق volume ساخته‌شده در آروان‌کلاد است.
- **`/mnt/arvanfs`**: مسیر محلی که می‌خواهیم NFS به آن متصل شود (همان فولدری که ساختیم).

### پرزیست کردن Mount در `/etc/fstab`

بعد از ریبوت، تمام mount‌های دستی پاک می‌شوند. برای اینکه بعد از هر بار خاموش و روشن شدن سرور، NFS دوباره به‌صورت خودکار mount شود، باید آن را به فایل `/etc/fstab` اضافه کنیم.

```bash
sudo nano /etc/fstab
```

این دستور فایل `/etc/fstab` را با ویرایشگر متنی `nano` باز می‌کند. `fstab` مخفف **File System Table** است و لیستی از تمام فضاهای ذخیره‌سازی‌ای است که باید هنگام بوت سیستم mount شوند.

خط زیر به انتهای این فایل اضافه شد:

```
192.168.1.3:/volumes/_nogroup/10416600-8423-4a3f-9afc-b07d8dfe38d2/b6cd7b74-2cfd-4f25-9072-7881887bed2e /mnt/arvanfs nfs4 rw,soft 0 0
```

توضیح هر بخش:
- **`192.168.1.3:/volumes/...`**: آدرس منبع NFS
- **`/mnt/arvanfs`**: مقصد (mount point)
- **`nfs4`**: نسخه‌ی پروتکل NFS (نسخه ۴)
- **`rw`**: مخفف **Read-Write**؛ یعنی هم خواندن هم نوشتن مجاز است.
- **`soft`**: اگر سرور NFS در دسترس نبود، عملیات با خطا پایان یابد (به جای اینکه سیستم هنگ کند).
- **`0 0`**: مقادیر مربوط به backup و بررسی فایل‌سیستم که هر دو غیرفعال هستند.

---

## ۳. نصب و پیکربندی Nginx و PHP-FPM

### Nginx چیست؟

Nginx (تلفظ: «انجین‌ایکس») یک **وب‌سرور** قدرتمند است. وظیفه‌اش این است که وقتی کاربری آدرس سایت شما را در مرورگر وارد می‌کند، درخواست را دریافت کرده و فایل‌های مناسب را برگرداند. Nginx به‌خودی‌خود PHP را اجرا نمی‌کند، به همین دلیل به PHP-FPM نیاز داریم.

### PHP-FPM چیست؟

PHP-FPM مخفف **PHP FastCGI Process Manager** است. این یک سرویس است که کدهای PHP را اجرا می‌کند. وقتی مرورگر یک فایل `.php` درخواست می‌کند، Nginx آن درخواست را به PHP-FPM می‌فرستد، PHP-FPM کد را اجرا می‌کند و نتیجه (HTML) را به Nginx برمی‌گرداند.

### نصب Nginx، PHP-FPM و افزونه‌ها

```bash
sudo apt install nginx php-fpm php-mysql php-cli php-curl php-gd php-mbstring php-xml php-zip unzip
```

این دستور تمام پکیج‌های مورد نیاز را نصب می‌کند:

| پکیج | کاربرد |
|---|---|
| `nginx` | وب‌سرور |
| `php-fpm` | اجراکننده کدهای PHP |
| `php-mysql` | اتصال PHP به پایگاه داده MySQL |
| `php-cli` | اجرای PHP از طریق خط فرمان |
| `php-curl` | ارسال و دریافت درخواست‌های HTTP از داخل PHP |
| `php-gd` | پردازش تصویر در PHP (نیاز وردپرس) |
| `php-mbstring` | پشتیبانی از کاراکترهای چندبایتی مثل فارسی |
| `php-xml` | پردازش XML در PHP |
| `php-zip` | کار با فایل‌های فشرده ZIP در PHP |
| `unzip` | ابزار خط‌فرمان برای استخراج فایل‌های zip |

### بررسی وضعیت PHP-FPM

```bash
systemctl status php8.1-fpm
```

- **`systemctl`**: ابزار مدیریت سرویس‌ها در لینوکس (systemd).
- **`status`**: وضعیت یک سرویس را نشان می‌دهد؛ آیا در حال اجراست؟ آخرین خطاها چه بودند؟
- **`php8.1-fpm`**: نام سرویس PHP-FPM نسخه ۸.۱

خروجی این دستور باید نشان دهد که سرویس `active (running)` است.

### پیکربندی PHP-FPM Pool

```bash
sudo nano /etc/php/8.1/fpm/pool.d/www.conf
```

این فایل تنظیمات **Pool** مربوط به PHP-FPM را نگه می‌دارد. Pool یعنی گروهی از پروسس‌های PHP که برای پاسخ به درخواست‌ها آماده‌اند.

```ini
pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 6
```

| تنظیم | توضیح |
|---|---|
| `pm = dynamic` | تعداد پروسس‌ها به‌صورت پویا (Dynamic) تنظیم می‌شود؛ یعنی بر اساس بار سرور، پروسس اضافه یا کم می‌شود. |
| `pm.max_children = 20` | حداکثر ۲۰ پروسس PHP می‌تواند همزمان اجرا شود. |
| `pm.start_servers = 4` | هنگام شروع سرویس، ۴ پروسس آماده به کار راه‌اندازی می‌شود. |
| `pm.min_spare_servers = 2` | همیشه حداقل ۲ پروسس بیکار (spare) باید در انتظار درخواست باشند. |
| `pm.max_spare_servers = 6` | حداکثر ۶ پروسس بیکار مجاز است؛ بیشتر از آن کشته می‌شوند تا حافظه آزاد شود. |

### پیکربندی OPcache در php.ini

```bash
sudo nano /etc/php/8.1/fpm/php.ini
```

```ini
opcache.enable=1
opcache.memory_consumption=128
opcache.max_accelerated_files=10000
opcache.revalidate_freq=2
```

**OPcache** یک سیستم کش برای PHP است. وقتی یک فایل PHP برای اولین بار اجرا می‌شود، PHP آن را به **کد ماشین** (bytecode) تبدیل می‌کند. OPcache این bytecode را در حافظه RAM نگه می‌دارد تا دفعات بعد نیازی به ترجمه مجدد نباشد. نتیجه: سرعت اجرای PHP به‌شدت افزایش پیدا می‌کند.

| تنظیم | توضیح |
|---|---|
| `opcache.enable=1` | OPcache را فعال می‌کند. |
| `opcache.memory_consumption=128` | ۱۲۸ مگابایت RAM برای ذخیره bytecodeها اختصاص می‌دهد. |
| `opcache.max_accelerated_files=10000` | حداکثر ۱۰۰۰۰ فایل PHP می‌توانند در کش باشند. |
| `opcache.revalidate_freq=2` | هر ۲ ثانیه یک‌بار بررسی می‌کند که آیا فایل‌های PHP تغییر کرده‌اند یا نه. |

### افزودن FastCGI Cache به nginx.conf

```bash
sudo nano /etc/nginx/nginx.conf
```

خط زیر اضافه شد:

```nginx
fastcgi_cache_path /var/cache/nginx levels=1:2 keys_zone=WORDPRESS:100m inactive=60m;
```

- **`fastcgi_cache_path`**: مسیر ذخیره‌سازی کش FastCGI را مشخص می‌کند.
- **`/var/cache/nginx`**: فولدری که فایل‌های کش در آن ذخیره می‌شوند.
- **`levels=1:2`**: ساختار زیرپوشه برای ذخیره‌سازی فایل‌های کش (برای جلوگیری از ایجاد خیلی فایل در یک فولدر).
- **`keys_zone=WORDPRESS:100m`**: یک ناحیه کش به نام `WORDPRESS` با ۱۰۰ مگابایت فضا در RAM تعریف می‌کند که کلیدهای کش در آن نگهداری می‌شوند.
- **`inactive=60m`**: اگر یک آیتم کش تا ۶۰ دقیقه استفاده نشد، حذف می‌شود.

---

## ۴. دریافت گواهی SSL با Certbot

### SSL چیست؟

SSL (یا TLS) پروتکلی است که ارتباط بین مرورگر کاربر و سرور شما را **رمزنگاری** می‌کند. وقتی سایت شما گواهی SSL داشته باشد، آدرس آن با `https://` شروع می‌شود و مرورگر آیکون قفل را نشان می‌دهد.

### Certbot چیست؟

Certbot یک ابزار رایگان از **Let's Encrypt** است که به‌صورت خودکار گواهی SSL معتبر برای دامنه شما صادر می‌کند.

### نصب Certbot

```bash
sudo apt install certbot python3-certbot-nginx
```

- **`certbot`**: ابزار اصلی دریافت گواهی SSL.
- **`python3-certbot-nginx`**: پلاگین Certbot برای Nginx که می‌تواند به‌صورت خودکار تنظیمات Nginx را برای SSL ویرایش کند.

### دریافت گواهی Wildcard

```bash
certbot -d *.ip2loc.ir --manual --preferred-challenges dns certonly
```

- **`-d *.ip2loc.ir`**: دامنه‌ای که می‌خواهیم برایش گواهی بگیریم. علامت `*` (wildcard) یعنی این گواهی برای تمام ساب‌دامنه‌ها مثل `www.ip2loc.ir`، `api.ip2loc.ir` و... معتبر است.
- **`--manual`**: فرایند تأیید دامنه را به‌صورت دستی انجام می‌دهیم (Certbot دستورالعمل می‌دهد و ما آن را اجرا می‌کنیم).
- **`--preferred-challenges dns`**: روش تأیید مالکیت دامنه را DNS انتخاب می‌کند. Certbot یک رکورد DNS خاص می‌خواهد که به پنل DNS دامنه‌تان اضافه کنید تا ثابت شود مالک دامنه هستید. (برای wildcard certificate این روش اجباری است.)
- **`certonly`**: فقط گواهی را دریافت کن و تنظیمات Nginx را دست نزن (ما خودمان تنظیم می‌کنیم).

---

## ۵. پیکربندی Nginx برای دامنه

فایل کانفیگ دامنه در مسیر `/etc/nginx/conf.d/` ساخته شد:

```nginx
server {
    listen 80;
    server_name ip2loc.ir;

    return 301 https://$host$request_uri;
}
```

این بلاک اول، هر درخواست HTTP (پورت ۸۰) را با **Redirect 301** به HTTPS هدایت می‌کند. کد ۳۰۱ یعنی این Redirect دائمی است (مرورگرها آن را کش می‌کنند).

```nginx
server {
    listen 443 ssl http2;
    server_name ip2loc.ir;

    root /mnt/arvanfs/wordpress;
    index index.php index.html;

    client_max_body_size 64M;

    ssl_certificate /etc/letsencrypt/live/ip2loc.ir/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ip2loc.ir/privkey.pem;

    add_header Strict-Transport-Security "max-age=31536000" always;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 30d;
        access_log off;
    }
}
```

توضیح هر بخش:

| دستور | توضیح |
|---|---|
| `listen 443 ssl http2` | روی پورت ۴۴۳ (HTTPS) گوش بده و از پروتکل HTTP/2 استفاده کن. |
| `root /mnt/arvanfs/wordpress` | فایل‌های سایت در این مسیر (روی NFS) قرار دارند. |
| `index index.php index.html` | اگر آدرس فولدر بود، اول `index.php` و بعد `index.html` را امتحان کن. |
| `client_max_body_size 64M` | حداکثر حجم فایل آپلودی ۶۴ مگابایت است (مهم برای آپلود تصویر در وردپرس). |
| `ssl_certificate` | مسیر فایل گواهی SSL. |
| `ssl_certificate_key` | مسیر کلید خصوصی SSL. |
| `Strict-Transport-Security` | هدر HSTS؛ به مرورگر می‌گوید این سایت را برای یک سال (`31536000` ثانیه) همیشه با HTTPS باز کن. |
| `try_files $uri $uri/ /index.php?$args` | ابتدا فایل درخواست‌شده را جستجو کن، اگر نبود فولدر را امتحان کن، اگر آن هم نبود به `index.php` پاس بده (این برای روتینگ وردپرس ضروری است). |
| `fastcgi_pass unix:/run/php/php8.1-fpm.sock` | درخواست‌های PHP را از طریق Unix Socket به PHP-FPM بفرست. |
| `expires 30d` | فایل‌های استاتیک (JS، CSS، تصاویر) را برای ۳۰ روز در مرورگر کاربر کش کن. |
| `access_log off` | لاگ دسترسی برای فایل‌های استاتیک غیرفعال شود تا فایل لاگ بی‌جهت بزرگ نشود. |

---

## ۶. مانیتورینگ

برای اینکه بدانیم سرورها در چه وضعیتی هستند (CPU، RAM، دیسک، شبکه)، از سه ابزار در کنار هم استفاده کردیم:

### Node Exporter چیست؟

**Node Exporter** یک برنامه‌ی سبک است که روی هر سرور نصب می‌شود و اطلاعات سخت‌افزاری آن سرور (مصرف CPU، RAM، دیسک، شبکه و...) را جمع‌آوری کرده و از طریق HTTP (معمولاً پورت `9100`) در اختیار می‌گذارد. به آن مثل یک **سنسور** فکر کنید که دائماً وضعیت سرور را اندازه می‌گیرد.

### Prometheus چیست؟

**Prometheus** یک سیستم **مانیتورینگ و جمع‌آوری داده** است. این سیستم به‌صورت منظم (مثلاً هر ۱۵ ثانیه) به Node Exporterهای نصب‌شده روی سرورها مراجعه می‌کند، داده‌ها را می‌خواند و در پایگاه داده‌ی خودش ذخیره می‌کند. به آن مثل یک **دفترچه ثبت اطلاعات** فکر کنید که هر چند ثانیه یک‌بار وضعیت همه سنسورها را می‌نویسد.

### Grafana چیست؟

**Grafana** یک ابزار **داشبورد و ویژوالیزیشن** است. داده‌هایی که Prometheus جمع‌آوری کرده را می‌خواند و آن‌ها را به‌صورت نمودارهای زیبا و قابل فهم نمایش می‌دهد. به آن مثل یک **صفحه کنترل** با نمودار و گراف فکر کنید که یک نگاه کافی است تا بفهمید همه چیز درست است یا نه.

**جمع‌بندی:**
```
سرور ۱ --> [Node Exporter] --> (port 9100)
سرور ۲ --> [Node Exporter] --> (port 9100)
                                    |
                              [Prometheus] -- هر ۱۵ ثانیه داده می‌کشد
                                    |
                              [Grafana] -- نمودار نشان می‌دهد
```

---

### نصب Node Exporter روی هر دو سرور

**ساخت یوزر اختصاصی:**

```bash
sudo useradd --no-create-home --shell /bin/false node_exporter
```

- **`useradd`**: یک یوزر جدید در سیستم می‌سازد.
- **`--no-create-home`**: برای این یوزر فولدر home نساز (چون به آن نیازی نداریم).
- **`--shell /bin/false`**: این یوزر نمی‌تواند وارد سیستم (login) شود. یک اقدام امنیتی است تا اگر کسی به نام این یوزر وارد شد، هیچ دسترسی نداشته باشد.
- **`node_exporter`**: نام یوزر.

**استخراج فایل‌های Node Exporter:**

```bash
tar -xzf node_exporter.tar.gz
```

- **`tar`**: ابزار کار با فایل‌های آرشیو در لینوکس.
- **`-x`**: عملیات استخراج (extract) را انجام بده.
- **`-z`**: فایل با gzip فشرده شده، آن را ابتدا از حالت فشرده خارج کن.
- **`-f`**: نام فایل آرشیو را مشخص می‌کند که اینجا `node_exporter.tar.gz` است.

**ساخت فایل سرویس systemd:**

```bash
sudo nano /etc/systemd/system/node_exporter.service
```

```ini
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
```

این فایل به **systemd** (سیستم مدیریت سرویس لینوکس) توضیح می‌دهد که Node Exporter چیست و چطور اجرا شود:

| بخش | توضیح |
|---|---|
| `Description` | توضیح مختصر سرویس |
| `After=network.target` | این سرویس را بعد از راه‌اندازی شبکه شروع کن |
| `User=node_exporter` | سرویس با یوزر `node_exporter` اجرا شود |
| `Group=node_exporter` | گروه اجرایی سرویس |
| `Type=simple` | این یک سرویس ساده است که یک پروسس راه‌اندازی می‌کند |
| `ExecStart=...` | دستور شروع سرویس |
| `WantedBy=multi-user.target` | این سرویس در حالت چند‌کاربره سیستم (حالت نرمال) فعال باشد |

**فعال‌سازی و اجرای سرویس:**

```bash
sudo systemctl daemon-reload
```

بعد از تغییر یا افزودن فایل‌های `.service`، باید به systemd بگوییم که تغییرات را دوباره بخواند. این دستور آن کار را می‌کند.

```bash
sudo systemctl enable node_exporter
```

سرویس Node Exporter را فعال می‌کند تا **بعد از هر بار ریبوت سرور** به‌صورت خودکار شروع به کار کند.

```bash
sudo systemctl start node_exporter
```

سرویس Node Exporter را **همین الان** شروع به کار می‌کند (بدون نیاز به ریبوت).

---

### پیکربندی Prometheus

یک سرور Prometheus از پنل آروان‌کلاد راه‌اندازی شد و یک volume اضافه شد تا داده‌ها بعد از ریبوت از بین نروند.

فایل کانفیگ `/etc/prometheus/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  scrape_timeout: 10s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node"
    static_configs:
      - targets: ["188.121.111.164:9100"]
        labels:
          role: "server-1"

      - targets: ["37.32.4.218:9100"]
        labels:
          role: "server-2"
```

| تنظیم | توضیح |
|---|---|
| `scrape_interval: 15s` | هر ۱۵ ثانیه داده جمع‌آوری کن |
| `scrape_timeout: 10s` | اگر بعد از ۱۰ ثانیه جوابی نیامد، عملیات را با خطا متوقف کن |
| `evaluation_interval: 15s` | هر ۱۵ ثانیه قوانین (rules) را ارزیابی کن |
| `job_name: "node"` | نام این گروه از هدف‌ها |
| `targets` | لیست سرورهایی که Node Exporter روی آن‌ها نصب است (IP:Port) |
| `labels` | برچسب‌هایی برای تشخیص سرورها از هم در Grafana |

---

### راه‌اندازی Grafana

Grafana از طریق پنل آروان‌کلاد نصب شد. سپس:

1. **اضافه کردن Prometheus به عنوان Data Source**: در تنظیمات Grafana، آدرس سرور Prometheus را وارد کردیم تا Grafana بتواند از آن داده بخواند.

2. **ایمپورت داشبورد**: به بخش **Dashboards → Import** رفته و ID شماره **1860** را وارد کردیم.

   داشبورد ۱۸۶۰ یک داشبورد آماده و معروف به نام **Node Exporter Full** است که صدها گراف آماده برای نمایش وضعیت سرور دارد و نیازی به ساخت از صفر نیست.

---

## ۷. پیکربندی فایروال

برای امنیت بیشتر، یک گروه فایروالی (Security Group) در پنل آروان‌کلاد ساخته شد. قوانین زیر اعمال شدند:

**Whitelist کردن IP‌های CDN آروان‌کلاد (برای HTTPS):**

تنها ترافیک ورودی HTTP/HTTPS از IP‌های CDN آروان مجاز است. CDN فعلاً از پروتکل QUIC (UDP) بین PoP و سرور پشتیبانی نمی‌کند، پس فقط TCP وایت‌لیست شد.

| رنج IP | Zone |
|---|---|
| `128.0.105.0/24` | Bamdad |
| `94.101.188.0/24` | Simin |
| `94.101.189.0/24` | Forough |

**Whitelist کردن IP‌های خروجی کانتینر Prometheus برای پورت 9100:**

تا Prometheus بتواند به Node Exporterهای روی سرورها دسترسی داشته باشد، IP‌های خروجی سرویس CaaS آروان‌کلاد برای پورت `9100` وایت‌لیست شدند.

---

## ۸. داکرایز کردن پروژه Next.js

### Docker چیست؟

Docker یک ابزار است که به شما اجازه می‌دهد برنامه‌تان را به همراه تمام وابستگی‌هایش (کتابخانه‌ها، تنظیمات، محیط اجرایی) داخل یک **Container** بسته‌بندی کنید. این Container روی هر سرور و سیستم‌عاملی که Docker داشته باشد، دقیقاً یکسان اجرا می‌شود. مشکل «روی کامپیوتر من کار می‌کرد!» دیگر وجود ندارد.

### Dockerfile

فایلی به نام `Dockerfile` در ریشه پروژه ساخته شد که دستورالعمل ساخت Image را دارد:

```dockerfile
FROM node:20-alpine AS base
```
از ایمیج پایه Node.js نسخه ۲۰ روی Alpine Linux استفاده کن. Alpine یک توزیع لینوکس بسیار سبک (~5MB) است که سایز نهایی ایمیج را کوچک نگه می‌دارد.

```dockerfile
FROM base AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./
RUN \
  if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then yarn global add pnpm && pnpm i --frozen-lockfile; \
  else echo "Lockfile not found." && npm i; \
  fi
```

این مرحله **deps** (وابستگی‌ها) نام دارد:
- `apk add libc6-compat`: یک کتابخانه سیستمی نصب می‌کند که برخی پکیج‌های Node به آن نیاز دارند.
- `COPY package.json ...`: فایل‌های قفل پکیج را کپی می‌کند.
- منطق شرطی: بررسی می‌کند که پروژه از کدام package manager استفاده می‌کند (yarn، npm یا pnpm) و وابستگی‌ها را نصب می‌کند.

```dockerfile
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build
```

این مرحله **builder** نام دارد:
- `COPY --from=deps`: فولدر `node_modules` را از مرحله قبل کپی می‌کند.
- `COPY . .`: تمام فایل‌های پروژه را کپی می‌کند.
- `npm run build`: پروژه Next.js را برای production بیلد می‌کند.

```dockerfile
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
CMD ["node", "server.js"]
```

این مرحله **runner** نام دارد (ایمیج نهایی):
- `ENV NODE_ENV=production`: محیط اجرا را production قرار می‌دهد تا بهینه‌سازی‌های لازم اعمال شوند.
- `addgroup / adduser`: یوزر و گروه غیر-root می‌سازد. اجرای برنامه با یوزر root خطرناک است.
- `COPY --from=builder`: فقط فایل‌های لازم برای اجرا (نه سورس کد) از مرحله build کپی می‌شوند. این ایمیج نهایی را بسیار کوچک‌تر می‌کند.
- `USER nextjs`: از این به بعد دستورات با یوزر `nextjs` اجرا می‌شوند.
- `EXPOSE 3000`: اعلام می‌کند که این Container روی پورت ۳۰۰۰ گوش می‌دهد.
- `CMD ["node", "server.js"]`: دستور پیش‌فرض اجرا هنگام راه‌اندازی Container.

### Build گرفتن از Dockerfile

```bash
docker build -t nextjs-blog .
```

- **`docker build`**: دستور ساخت Docker Image از Dockerfile.
- **`-t nextjs-blog`**: به ایمیج ساخته‌شده تگ (نام) `nextjs-blog` بده. (`-t` مخفف **tag** است)
- **`.`**: Dockerfile را در فولدر جاری (دایرکتوری فعلی) پیدا کن.

---

## ۹. Container Registry و دیپلوی روی CaaS

### Container Registry چیست؟

Container Registry یک **مخزن** (انبار) برای نگهداری Docker Imageهاست. مثل GitHub برای کد، اما برای ایمیج‌های Docker. در اینجا از سرویس Container Registry آروان‌کلاد استفاده شد.

### لاگین به Registry

```bash
docker login registry-8595781cfa-astroadre.apps.ir-central1.arvancaas.ir
```

- **`docker login`**: به یک Container Registry احراز هویت می‌کند.
- **`registry-8595781cfa-astroadre.apps.ir-central1.arvancaas.ir`**: آدرس Container Registry آروان‌کلاد. این آدرس منحصربه‌فرد برای هر پروژه است.

بعد از اجرای این دستور، Docker نام کاربری و رمز عبور می‌خواهد که همان اعتبارنامه‌های پنل آروان‌کلاد هستند.

### Tag زدن به ایمیج

```bash
docker tag 8dd25df493a7 registry-8595781cfa-astroadre.apps.ir-central1.arvancaas.ir/kimblog:latest
```

- **`docker tag`**: به یک ایمیج موجود یک نام جدید (tag) اضافه می‌کند. مثل زدن یک برچسب روی یک بسته.
- **`8dd25df493a7`**: این ID منحصربه‌فرد ایمیجی است که در مرحله `docker build` ساختیم. می‌توانید این ID را با دستور `docker images` ببینید.
- **`registry-8595781cfa-astroadre.apps.ir-central1.arvancaas.ir/kimblog:latest`**: نام کامل جدید ایمیج که شامل:
  - **آدرس Registry**: `registry-8595781cfa-astroadre.apps.ir-central1.arvancaas.ir`
  - **نام ایمیج**: `kimblog`
  - **تگ نسخه**: `latest` (یعنی آخرین نسخه)

این نام‌گذاری به Docker می‌گوید که این ایمیج باید به کجا push شود.

### Push کردن ایمیج به Registry

```bash
docker push registry-8595781cfa-astroadre.apps.ir-central1.arvancaas.ir/kimblog:latest
```

- **`docker push`**: ایمیج لوکال را به Container Registry آپلود می‌کند.
- **`registry-8595781cfa-astroadre.apps.ir-central1.arvancaas.ir/kimblog:latest`**: آدرس کامل ایمیج در Registry که باید به آن push شود.

بعد از این دستور، ایمیج شما در فضای ابری آروان‌کلاد ذخیره شده و آماده‌ی دیپلوی است.

### دیپلوی روی CaaS

**CaaS** مخفف **Container as a Service** است؛ یعنی یک پلتفرم ابری که مدیریت اجرای Containerها را برعهده می‌گیرد. به جای اینکه خودتان Docker را روی سرور مدیریت کنید، فقط ایمیج را مشخص می‌کنید و پلتفرم همه چیز را مدیریت می‌کند.

از طریق پنل آروان‌کلاد، اپلیکیشن با استفاده از ایمیج push شده روی CaaS ساخته شد و دامنه به آن اضافه گردید.

---

## جمع‌بندی معماری

```
کاربر
  |
  | (HTTPS)
  v
[CDN آروان‌کلاد]
  |
  | (TCP - فقط IP های وایت‌لیست شده)
  v
[Nginx روی سرور ۱]
  |
  | (FastCGI)
  v
[PHP-FPM]     [NFS - فایل‌های وردپرس]
  |                    |
  +--------------------+
         |
         v
   [شبکه خصوصی - 192.168.1.0/24]
         |
         v
[سرور ۲ - Prometheus + Grafana]
  |
  | (scrape - port 9100)
  v
[Node Exporter روی هر دو سرور]


[CaaS آروان‌کلاد]
  |
  | (Container Registry)
  v
[اپلیکیشن Next.js - دیپلوی شده]
```

---

> **نکته:** سرویس ELK Stack (Elasticsearch, Logstash, Kibana) برای مدیریت لاگ‌ها هنوز اضافه نشده و در مراحل آینده به زیرساخت اضافه خواهد شد.
