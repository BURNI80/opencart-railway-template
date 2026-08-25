# OpenCart — Railway Template

Deploy [OpenCart 4.1.0.4](https://github.com/opencart/opencart) on Railway with a fully automated setup. Storefront and admin panel ready in minutes.

## What's Included

| Service | Image / Source | Purpose |
|---------|---------------|---------|
| **OpenCart** | `php:8.1-apache` + OpenCart 4.1.0.4 | E-commerce storefront & admin |
| **MySQL** | `mariadb:10.6` (Railway managed) | Database |

## Estimated Cost

On Railway's Hobby plan ($5/mes credit included), a small store runs ~$3–5/month. Actual cost depends on traffic and database size.

## Quick Deploy

1. Click **Deploy Template** above
2. Railway creates both services and links them automatically
3. Wait ~3–5 minutes for the first deploy
4. Visit your store URL

## Post-Deploy Steps

1. **Access admin panel** at `https://<your-url>/admin/`
2. **Login** with the credentials you set (defaults: `admin` / `opencart`)
3. **Change admin password** immediately
4. **Configure your store**: System → Settings (store name, URL, email, etc.)
5. **Add products**: Catalog → Products
6. **Set up payment & shipping**: Extensions → Extensions

## Environment Variables

### Auto-provided by Railway (from linked MySQL service)

| Variable | Description |
|----------|-------------|
| `MYSQLHOST` | Database hostname |
| `MYSQLPORT` | Database port (`3306`) |
| `MYSQLUSER` | Database username |
| `MYSQLPASSWORD` | Database password |
| `MYSQLDATABASE` | Database name (`opencart`) |

### User-configurable

| Variable | Description | Default |
|----------|-------------|---------|
| `ADMIN_USERNAME` | Admin panel username | `admin` |
| `ADMIN_PASSWORD` | Admin panel password | `opencart` |
| `ADMIN_EMAIL` | Admin email address | `admin@example.com` |
| `DB_PREFIX` | Database table prefix | `oc_` |

## Local Development

```bash
git clone https://github.com/your-user/opencart-railway-template.git
cd opencart-railway-template
docker compose up -d
```

- Storefront: http://localhost:8080
- Admin panel: http://localhost:8080/admin/

```bash
docker compose down -v   # stop and remove all data
```

## Architecture

```
┌─────────────────┐     ┌─────────────────┐
│    OpenCart      │────▶│     MySQL       │
│  php:8.1-apache  │     │  mariadb:10.6   │
│  port 80         │     │  port 3306      │
└─────────────────┘     └─────────────────┘
        │
        ▼
  /var/www/html/system/storage  (volume — persists uploads, logs, cache)
```

- **First deploy**: CLI installer runs, creates DB schema, generates config files
- **Subsequent deploys**: Detects existing DB, regenerates config from env vars
- **Private networking**: OpenCart connects to MySQL via `mysql.railway.internal`

## Troubleshooting

### "Database Connection Failed"
- Ensure the MySQL service is linked in your Railway project
- Check the MySQL service is running in the Railway dashboard
- Wait 1–2 minutes for the database to fully initialize

### "Installation Incomplete" / Installer page showing
- The CLI installer may have failed. Check deploy logs
- Ensure `ADMIN_PASSWORD` is between 5–20 characters

### 500 Internal Server Error
- Check Railway deploy logs for the specific PHP error
- Verify all env vars are set correctly

### SEO URLs not working
- `.htaccess` rewrite rules are included in the Apache config
- Clear OpenCart cache: admin → Dashboard → clear icon

## License

GPL v2 — same as [OpenCart](https://github.com/opencart/opencart/blob/master/LICENSE.md).
