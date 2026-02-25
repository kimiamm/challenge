# مستندات انجام چالش

این مستندات، مراحل کامل راه‌اندازی انجام چالش راه‌اندازی سرور ابری، وب‌سرور، مانیتورینگ و دیپلوی اپلیکیشن را به‌صورت گام‌به‌گام توضیح می‌دهد.

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
                             |   CDN آروان‌كلاد     |
                             +--+------+-------+--+
                                |      |       |
                   Load Balance |      | Load  | ارسال لاگ
                                |      | Balance|
                                |      |       |
              +-----------------+      +---+   +------------------+
              |                            |                      |
              v                            v                      v
+----------------------------+  +----------------------------+  +-----------------------+
|         Server 1           |  |         Server 2           |  |       ELK Stack       |
|   Nginx + PHP-FPM          |  |   Nginx + PHP-FPM          |  |  Elasticsearch        |
|   Node Exporter :9100      |  |   Node Exporter :9100      |  |  Logstash             |
+-----+------------+---------+  +----+------------+----------+  |  Kibana               |
      |            |                 |            |              +-----------+-----------+
      |  شبکه    |                 |.     شبکه    |                          |
      |  خصوصی    |.                |     خصوصی   |                          | Backup
      v            v                 v            v                          v
+----------+  +---------+  +----------+  +---------+             +---------------------+
|   NFS    |  |  DBaaS  |  |   NFS    |  |  DBaaS  |             |   Object Storage    |
|   File   |  |  MySQL  |  |   File   |  |  MySQL  |             |  (بك‌آپ لاگ‌ها)        |
| Storage  |  |         |  | Storage  |  |         |             +---------------------+
+----------+  +---------+  +----------+  +---------+


 +------------------------------------------------------------------+
 |                     CaaS آروان‌كلاد                                |
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
 |                                            v                     |
 |                                  +------------------+            |
 |                                  |     Grafana      |            |
 |                                  |    Dashboard     |            |
 |                                  +------------------+            |
 +------------------------------------------------------------------+
```

---

## ۱. ایجاد سرورهای ابری

ابتدا دو سرور ابری در دیتاسنتر **شهریار** از آروان‌کلاد ساخته شد. این دو سرور پایه‌ی کل زیرساخت پروژه هستند:
هدف از ایجاد دو سرور مختلف HA بودن معماری است.

---

## ۲. شبکه خصوصی و NFS

### شبکه خصوصی چیست؟

شبکه خصوصی (Private Network) یک شبکه داخلی است که فقط سرورهای داخل آن می‌توانند با هم ارتباط برقرار کنند و از اینترنت عمومی قابل دسترسی نیست. این کار باعث می‌شود انتقال داده بین سرورها **امن‌تر و سریع‌تر** انجام شود.

* **ساب‌نت:** `192.168.1.0/24` → آدرس‌های IP از `192.168.1.1` تا `192.168.1.254`
* **DHCP:** پروتکلی که به هر سرور به‌صورت خودکار یک IP اختصاص می‌دهد.

### NFS چیست؟

NFS یا **Network File System** به شما امکان می‌دهد یک فولدر روی یک سرور را روی سرور دیگر **mount** کنید؛ یعنی انگار آن فولدر روی خود سرور دوم است.

در این پروژه، یک **File Storage** از پنل آروان‌کلاد ساخته شد و از طریق NFS به سرورها متصل شد تا فایل‌های وردپرس روی آن ذخیره شوند.

### مراحل پیاده‌سازی NFS

1. **نصب کلاینت NFS**

```bash
sudo apt-get install nfs-common
```

2. **ساخت فولدر mount**

```bash
sudo mkdir /mnt/arvanfs
```

3. **تغییر مالکیت فولدر**

```bash
sudo chown -R www-data:www-data /mnt/arvanfs
```

4. **Mount کردن فضای NFS**

```bash
sudo mount -t nfs "192.168.1.3:/volumes/.../b6cd7b74-2cfd-4f25-9072-7881887bed2e" /mnt/arvanfs
```

5. **اضافه کردن Mount به `/etc/fstab`**

```bash
192.168.1.3:/volumes/.../b6cd7b74-2cfd-4f25-9072-7881887bed2e /mnt/arvanfs nfs4 rw,soft 0 0
```

> این کار باعث می‌شود بعد از هر ریبوت، NFS به‌صورت خودکار متصل شود.

---

## ۳. نصب و پیکربندی Nginx و PHP-FPM

### Nginx چیست؟

**Nginx** یک وب‌سرور بسیار سریع و سبک است که وظیفه‌ی اصلی آن دریافت درخواست‌های کاربران از مرورگر و ارسال پاسخ مناسب (HTML، فایل‌های استاتیک یا درخواست‌های PHP) است. Nginx علاوه بر وب‌سروری، قابلیت‌هایی مثل **Load Balancing**، **Reverse Proxy** و مدیریت **HTTP/2** را نیز ارائه می‌دهد.

از آنجا که Nginx به‌صورت مستقیم کدهای PHP را اجرا نمی‌کند، برای پردازش فایل‌های PHP به سرویس **PHP-FPM** نیاز دارد که درخواست‌ها را به صورت امن و بهینه اجرا می‌کند.


### PHP-FPM چیست؟


**PHP-FPM** مخفف **PHP FastCGI Process Manager** است. این سرویس مسئول اجرای کدهای PHP و بازگرداندن خروجی به وب‌سرور است.

وقتی مرورگر کاربر یک فایل `.php` را درخواست می‌کند:

1. Nginx درخواست را دریافت می‌کند.
2. آن را به PHP-FPM ارسال می‌کند.
3. PHP-FPM کد PHP را اجرا کرده و خروجی HTML تولید می‌کند.
4. خروجی به Nginx بازگردانده می‌شود تا به مرورگر کاربر ارسال شود.

این جداسازی باعث می‌شود وب‌سرور و پردازش PHP به‌صورت مستقل و بهینه اجرا شوند و مدیریت منابع سرور آسان‌تر باشد. همچنین امنیت و سرعت پردازش درخواست‌ها افزایش پیدا می‌کند.



### نصب پکیج‌ها

```bash
sudo apt install nginx php-fpm php-mysql php-cli php-curl php-gd php-mbstring php-xml php-zip unzip
```

| پکیج         | کاربرد                          |
| ------------ | ------------------------------- |
| nginx        | وب‌سرور                         |
| php-fpm      | اجرای کدهای PHP                 |
| php-mysql    | اتصال به MySQL                  |
| php-cli      | اجرای PHP از خط فرمان           |
| php-curl     | ارسال/دریافت درخواست HTTP       |
| php-gd       | پردازش تصویر                    |
| php-mbstring | پشتیبانی از کاراکترهای چندبایتی |
| php-xml      | پردازش XML                      |
| php-zip      | کار با ZIP                      |
| unzip        | استخراج فایل ZIP                |

### بررسی وضعیت PHP-FPM

```bash
systemctl status php8.1-fpm
```

### پیکربندی PHP-FPM Pool

```ini
pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 6
```

### فعال‌سازی OPcache

```ini
opcache.enable=1
opcache.memory_consumption=128
opcache.max_accelerated_files=10000
opcache.revalidate_freq=2
```

> OPcache سرعت اجرای PHP را با ذخیره bytecode فایل‌ها در حافظه RAM افزایش می‌دهد.

### افزودن FastCGI Cache به Nginx

```nginx
fastcgi_cache_path /var/cache/nginx levels=1:2 keys_zone=WORDPRESS:100m inactive=60m;
```

---

## ۴. دریافت گواهی SSL با Certbot


### SSL چیست؟

**SSL** (Secure Sockets Layer) یا نسخه‌ی جدیدتر آن **TLS**، پروتکلی است که ارتباط بین مرورگر کاربر و سرور را **رمزنگاری** می‌کند. با فعال بودن SSL، تمام داده‌های ارسال و دریافت شده از جمله اطلاعات فرم‌ها، کوکی‌ها و درخواست‌های API به‌صورت امن منتقل می‌شوند و امکان شنود یا تغییر داده‌ها توسط افراد ثالث به حداقل می‌رسد. وقتی سایت شما SSL داشته باشد، آدرس آن با `https://` شروع شده و مرورگر کاربر یک آیکون قفل نمایش می‌دهد که نشان‌دهنده‌ی امنیت و اعتماد سایت است.

استفاده از SSL علاوه بر امنیت، روی **سئو و اعتماد کاربران** نیز تأثیر مثبت دارد و بسیاری از مرورگرها سایت‌های بدون HTTPS را با هشدار امنیتی نشان می‌دهند.

---

### Certbot چیست؟

**Certbot** یک ابزار رایگان و متن‌باز از شرکت **Let's Encrypt** است که فرآیند دریافت و نصب گواهی SSL را به‌طور کامل خودکار می‌کند. این ابزار می‌تواند برای دامنه‌های ساده یا Wildcard، گواهی معتبر صادر کرده و به صورت خودکار وب‌سرور شما (Nginx یا Apache) را پیکربندی کند تا HTTPS فعال شود.

مزیت اصلی Certbot این است که نیاز به تنظیمات دستی پیچیده را حذف می‌کند و امکان **تمدید خودکار گواهی‌ها** را نیز فراهم می‌سازد. با استفاده از Certbot، امنیت سایت شما بدون دردسر و به شکل استاندارد جهانی تامین می‌شود، در حالی که فرآیند نصب و مدیریت SSL به سادگی چند دستور خط فرمان انجام می‌گیرد.



### نصب و دریافت گواهی

```bash
sudo apt install certbot python3-certbot-nginx
certbot -d *.ip2loc.ir --manual --preferred-challenges dns certonly
```

> گواهی wildcard برای تمام ساب‌دامنه‌ها معتبر است.

---

## ۵. پیکربندی Nginx برای دامنه

```nginx
server {
    listen 80;
    server_name ip2loc.ir;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ip2loc.ir;

    root /mnt/arvanfs/wordpress;
    index index.php index.html;

    ssl_certificate /etc/letsencrypt/live/ip2loc.ir/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ip2loc.ir/privkey.pem;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
    }
}
```

سپس وارد دایکتوری که به عنوان root مشخص شده میشویم و با استفاده از wget فایل وردپرس را دانلود و unzip میکنیم : 

```bash
wget https://fa.wordpress.org/latest-fa_IR.zip
unzip latest-fa_IR.zip
```

---
## ۶. مانیتورینگ سرورها

برای پایش وضعیت سرورها و زیرساخت‌ها، از سه ابزار اصلی استفاده شده است:

* **Node Exporter:** یک ابزار سبک که روی هر سرور نصب می‌شود و اطلاعات سخت‌افزاری سرور مانند مصرف CPU، RAM، دیسک و شبکه را جمع‌آوری می‌کند.
* **Prometheus:** یک سیستم پایش و ذخیره‌سازی داده‌ها. Prometheus به‌صورت دوره‌ای داده‌ها را از Node Exporter جمع‌آوری می‌کند و آن‌ها را در پایگاه داده داخلی خود ذخیره می‌کند.
* **Grafana:** ابزاری برای نمایش داده‌های جمع‌آوری شده به صورت داشبوردهای گرافیکی. با Grafana می‌توان نمودارها و گراف‌های قابل فهمی از وضعیت سرورها و سرویس‌ها ایجاد کرد.

### معماری کلی

```
سرور ۱/۲ --> Node Exporter --> Prometheus --> Grafana
```

در این معماری، Node Exporter داده‌ها را تولید می‌کند، Prometheus آن‌ها را جمع‌آوری و ذخیره می‌کند و Grafana داده‌ها را به شکل داشبوردهای تعاملی نمایش می‌دهد.


### راه‌اندازی Grafana و Prometheus در CaaS

**Grafana** از طریق پنل CaaS و با گزینه‌ی «راه‌اندازی با ایمیج داکر» نصب شد. برای مدیریت امنیت، متغیرهای محیطی زیر تنظیم شدند:

```
env:
  - name: GF_SECURITY_ADMIN_USER
    value: admin
  - name: GF_SECURITY_ADMIN_PASSWORD
    value: admin123
```

برای نگه‌داری دائمی داده‌های Grafana، یک **Volume** اضافه شد:

```
- name: grafana-storage
  mountPath: /var/lib/grafana
```

استفاده از Volume باعث می‌شود حتی اگر Container یا سرور Grafana ریست شود، داده‌ها و تنظیمات داشبوردها حفظ شوند و از دست نروند.

سپس از طریق پنل CaaS، دامنه مربوط به Grafana ایجاد شد تا داشبوردها با URL مشخص قابل دسترسی باشند.

---

برای **Prometheus** نیز مشابه Grafana عمل شد: از طریق پنل CaaS یک سرویس Prometheus با ایمیج Docker راه‌اندازی شد و اما کانفیگ آن از طریق پنل به شکل secret تعریف میشد نه configmap و Volume به Container اضافه شد تا دیتای آن حفظ شود
فایل اصلی کانفیگ Prometheus به شکل زیر است:

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

### توضیح هر بخش

**global:** تنظیمات سراسری Prometheus که روی همه jobها اعمال می‌شود.

* **scrape_interval: 15s**
  هر ۱۵ ثانیه داده‌ها از تمام targetها جمع‌آوری می‌شود.
* **scrape_timeout: 10s**
  اگر یک target در کمتر از ۱۰ ثانیه پاسخ ندهد، عملیات جمع‌آوری با خطا پایان می‌یابد.
* **evaluation_interval: 15s**
  Prometheus هر ۱۵ ثانیه قواعد و alertهای تعریف‌شده را بررسی می‌کند.

---

**scrape_configs:** تعریف jobهایی که Prometheus داده‌ها را از آن‌ها می‌خواند.

1. **job_name: "prometheus"**

   * Prometheus خودش را پایش می‌کند.
   * **targets: ["localhost:9090"]**
     Prometheus داده‌های خودش را از همین سرور و پورت 9090 جمع‌آوری می‌کند.

2. **job_name: "node"**

   * داده‌های سخت‌افزاری سرورها از Node Exporter جمع‌آوری می‌شود.
   * **static_configs:** مشخص کردن آیپی و پورت سرورها.

     * **targets: ["188.121.111.164:9100"]**
       داده‌های سرور ۱ از Node Exporter روی پورت 9100 خوانده می‌شود.
       **labels: role: "server-1"**
       یک برچسب برای شناسایی سرور ۱ در داشبورد و alertها.
     * **targets: ["37.32.4.218:9100"]**
       داده‌های سرور ۲ از Node Exporter روی پورت 9100 خوانده می‌شود.
       **labels: role: "server-2"**
       برچسب برای شناسایی سرور ۲.

---

این کانفیگ باعث می‌شود Prometheus داده‌های سخت‌افزاری هر دو سرور و وضعیت خودش را به‌صورت **دوره‌ای و پایدار** جمع‌آوری کرده و برای تحلیل در Grafana آماده کند.


Volumeهای مرتبط:

```
volumeMounts:
  - name: data-x0dbpetx
    mountPath: /etc/prometheus/prometheus.yml
    subPath: prometheus.yml
  - name: prom-kimi-disk-d85lw
    mountPath: /prometheus
```

اضافه کردن این Volumeها تضمین می‌کند که **داده‌های Prometheus و کانفیگ‌ها بین ریستارت‌ها یا ریپلوی‌ها حفظ شوند** و از دست رفتن داده‌ها رخ ندهد.

---

## فایروال و دسترسی‌ها

برای امنیت بیشتر، قوانین فایروال به شکل زیر اعمال شدند:

* **وایت‌لیست CDN آروان‌کلاد:** تنها ترافیک ورودی HTTP/HTTPS از آیپی‌های CDN مجاز است.
* **وایت‌لیست IP Prometheus:** برای دسترسی به Node Exporter روی پورت 9100.
* **وایت‌لیست IP سرورهای ارسال لاگ CDN:** برای دسترسی به Logstash روی پورت 5140.

این تنظیمات تضمین می‌کنند که فقط سرویس‌ها و منابع مشخص، بتوانند به سرورها و کانتینرها دسترسی داشته باشند و حملات احتمالی محدود شوند.


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

عالی، می‌توانیم بخش ELK را دقیق و مرحله‌به‌مرحله به سبک قبلی به متن اضافه کنیم، با توضیح کامل هر سرویس، کانفیگ و بکاپ، بدون اینکه چیزی خلاصه شود. نسخه بازنویسی‌شده:

---

## ۱۰. راه‌اندازی ELK Stack (Elasticsearch, Logstash, Kibana)

برای جمع‌آوری، پردازش و نمایش لاگ‌ها از **ELK Stack** استفاده شد. این مجموعه شامل سه سرویس است:

* **Elasticsearch:** پایگاه داده‌ی لاگ‌ها و موتور جستجو
* **Logstash:** پردازش و تبدیل لاگ‌ها
* **Kibana:** داشبورد و ویژوالیزیشن داده‌ها

### ۱۰.۱ فایل `docker-compose.yml`

```yaml
version: '3'

services:

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.17.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=true
      - ELASTIC_PASSWORD=Kimi@123
      - "ES_JAVA_OPTS=-Xms1g -Xmx1g"
    volumes:
      - ./elasticsearch-data:/usr/share/elasticsearch/data
    ports:
      - 9200:9200
    healthcheck:
      test: ["CMD-SHELL", "curl -u elastic:Kimi@123 -f http://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: always
    networks:
      - monitoring-stack-net

  logstash:
    image: docker.elastic.co/logstash/logstash:7.17.0
    container_name: logstash
    volumes:
      - ./logstash/pipeline:/usr/share/logstash/pipeline:ro
      - ./logstash/config/logstash.yml:/usr/share/logstash/config/logstash.yml:ro
    ports:
      - 5140:5140/tcp
      - 5140:5140/udp
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:9600/_node/stats/pipelines || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: always
    networks:
      - monitoring-stack-net
    depends_on:
      - elasticsearch

  kibana:
    image: docker.elastic.co/kibana/kibana:7.17.0
    container_name: kibana
    ports:
      - 5601:5601
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=elastic
      - ELASTICSEARCH_PASSWORD=Kimi@123
      - SERVER_PUBLICBASEURL=https://kibana.ip2loc.ir
    healthcheck:
      test: ["CMD-SHELL", "curl -u elastic:Kimi@123 -f http://localhost:5601/api/status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: always
    networks:
      - monitoring-stack-net
    depends_on:
      - elasticsearch

networks:
  monitoring-stack-net:
    driver: bridge
```

**توضیح سرویس‌ها:**

* **Elasticsearch:**

  * یک **single-node cluster** راه‌اندازی می‌کند
  * رمز عبور و گزینه‌های Java برای مدیریت حافظه تعیین شده‌اند
  * داده‌ها روی فولدر `./elasticsearch-data` ذخیره می‌شوند تا بعد از ریبوت از بین نروند

* **Logstash:**

  * دریافت و پردازش لاگ‌ها از TCP/UDP پورت 5140
  * فایل‌های pipeline و کانفیگ از فولدرهای محلی mount شده‌اند
  * وابسته به Elasticsearch است (`depends_on`)

* **Kibana:**

  * داشبورد گرافیکی برای مشاهده لاگ‌ها
  * به Elasticsearch متصل می‌شود و از HTTPS قابل دسترسی است
  * بعد از استارت Elasticsearch، Kibana به‌صورت خودکار بالا می‌آید

---

### ۱۰.۲ کانفیگ Logstash (`pipeline/logstash.conf`)

```conf
input {
  udp {
    port => 5140
    type => "syslog"
    codec => plain
    ecs_compatibility => disabled
  }
  tcp {
    port => 5140
    type => "syslog"
    codec => plain
    ecs_compatibility => disabled
  }
}

filter {
  grok {
    match => {
      "message" => "<%{NUMBER:syslog_pri}> %{TIMESTAMP_ISO8601:syslog_timestamp} %{HOSTNAME:syslog_host} %{WORD:syslog_program}(?:\[%{NUMBER:syslog_pid}\])?: %{GREEDYDATA:syslog_message}"
    }
    ecs_compatibility => disabled
  }

  json {
    source => "syslog_message"
    target => "log"
    skip_on_invalid_json => true
  }

  ruby {
    code => "
      log = event.get('log')
      if log.is_a?(Hash)
        log.each { |k, v| event.set(k, v) }
      end
      event.remove('log')
    "
  }

  date {
    match => ["iso_timestamp", "ISO8601"]
    target => "@timestamp"
  }

  mutate {
    remove_field => [
      "message", "syslog_message", "syslog_timestamp",
      "iso_timestamp", "timestamp", "host", "@version"
    ]
  }
}

output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    user => "elastic"
    password => "Kimi@123"
    ecs_compatibility => disabled
    index => "cdn-logs-%{+YYYY.MM.dd}"
    ilm_enabled => false
    manage_template => false
  }

  stdout {
    codec => rubydebug
  }
}
```

**توضیح کانفیگ:**

* **input:** دریافت لاگ از UDP و TCP پورت 5140

* **filter:**

  * `grok`: ساختار اولیه لاگ را استخراج می‌کند
  * `json`: تبدیل پیام‌های JSON به فیلدهای مجزا
  * `ruby`: باز کردن nested JSON
  * `date`: زمان لاگ را به `@timestamp` استاندارد تبدیل می‌کند
  * `mutate`: حذف فیلدهای اضافی

* **output:**

  * ارسال داده‌ها به Elasticsearch با نام ایندکس روزانه `cdn-logs-YYYY.MM.DD`
  * نمایش لاگ‌ها در کنسول با `stdout`

---

### ۱۰.۳ بکاپ‌گیری از Elasticsearch

اسکریپت زیر لاگ‌ها را از ایندکس Elasticsearch دریافت و به S3 آپلود می‌کند:

```bash
#!/bin/bash

ES_HOST="http://188.121.107.139:9200"
ES_USER="elastic"
ES_PASS="Kimi%40123"

INDEXES=("cdn-logs-2026.02.24")
OUTPUT_FILE="elastic_data.json"
S3_BUCKET="kimi-ch"

if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Creating new output file."
    echo "[]" > "$OUTPUT_FILE"
fi

ALL_DATA="[]"

for index in "${INDEXES[@]}"; do
    echo "Fetching data from $index..."

    DUMP_FILE=$(mktemp)
    rm -f "$DUMP_FILE"

    elasticdump \
        --input="http://${ES_USER}:${ES_PASS}@188.121.107.139:9200/${index}" \
        --output="$DUMP_FILE" \
        --type=data \
        --quiet

    if [ -f "$DUMP_FILE" ]; then
        INDEX_DATA=$(jq -c '._source' "$DUMP_FILE" | jq -s 'sort_by(."@timestamp")')
        ALL_DATA=$(echo "$ALL_DATA $INDEX_DATA" | jq -s 'add | unique_by(."@timestamp")')
        rm -f "$DUMP_FILE"
    else
        echo "No data returned for $index"
    fi
done

if [ "$ALL_DATA" != "$(cat "$OUTPUT_FILE")" ]; then
    echo "New data found. Updating file."
    echo "$ALL_DATA" > "$OUTPUT_FILE"

    echo "Uploading to S3..."
    rclone copy "$OUTPUT_FILE" s3:${S3_BUCKET}/ --progress
    echo "Upload complete."
else
    echo "No new data. All received data are duplicates."
fi
```

**توضیح بکاپ:**

* اتصال به Elasticsearch با کاربر `elastic`
* استخراج داده‌های ایندکس مشخص شده با `elasticdump`
* حذف داده‌های تکراری با `jq`
* ذخیره در فایل `elastic_data.json`
* آپلود به S3 با `rclone`
