# OpenCart — Railway Template

Dashboard de [OpenCart 4.1.0.4](https://github.com/opencart/opencart) listo para desplegar en **Railway** con un clic. Tienda y panel de administración funcionando en minutos.

> **Pensado para la capa gratuita de Railway.** Un único contenedor (Apache + PHP + MariaDB embebido) con volumen para datos persistentes. Sin servicios extra que sumen costes.

---

## Deploy en Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/IvqCee?utm_campaign=opencart)

Al desplegar, el formulario de Railway te pide **las credenciales del admin** (usuario, contraseña y email). Pones las tuyas y listo — no hay credenciales por defecto hardcodeadas.

---

## Credenciales (las pones tú al desplegar)

| Campo | Qué es |
|-------|--------|
| **Usuario admin** | Usuario del panel de administración (p. ej. `admin`) |
| **Contraseña admin** | La contraseña que elijas (mín. 5 caracteres) |
| **Email admin** | Email del administrador |

> ⚠️ Tras el deploy, entra en `/admin/` con esas credenciales. Puedes cambiarlas después en *System → Users → Users*.
> - **URL tienda:** la que te asigne Railway (algo como `https://tu-tienda.up.railway.app`)
> - **URL admin:** `https://tu-tienda.up.railway.app/admin/`

---

## Qué incluye

Un solo servicio con todo dentro (arquitectura *todo-en-uno* para mínimos costes):

| Componente | Detalle |
|------------|---------|
| **Web server** | Apache 2.4 (mod_rewrite + headers), MPM prefork |
| **PHP** | 8.1 (extensión `gd` con JPEG/FreeType, `mysqli`, `mbstring`, `zip`, `bcmath`, `pdo_mysql`) |
| **Base de datos** | **MariaDB embebido** (arranca dentro del mismo contenedor, `127.0.0.1:3306`) |
| **OpenCart** | 4.1.0.4 (tienda + panel admin) |
| **Datos persistentes** | Volumen montado en `/var/lib/mysql` (la base de datos sobrevive a los redeploys) |

En el arranque, un instalador automático (PHP) detecta si la base de datos ya está instalada:
- **Primer deploy:** crea las 159 tablas del esquema, importa los datos de ejemplo y crea el usuario admin.
- **Deploys posteriores:** si el admin ya existe, **no reinstala** — solo regenera los `config.php` a partir de las variables de entorno y sigue.

---

## Cómo desplegar (Railway)

1. Pulsa el botón **Deploy on Railway** de arriba (o abre `https://railway.com/new/template/IvqCee`).
2. En el formulario, introduce tus **credenciales de admin** (usuario, contraseña y email).
3. Railway construye la imagen y monta el volumen en `/var/lib/mysql` (persistencia).
4. Espera 2–4 minutos a que el primer deploy termine (healthcheck verifica que la tienda responde).
5. Abre tu URL y verás la tienda. Entra en `/admin/` con las credenciales que pusiste.

### Configuración recomendada tras el despliegue
1. **Configura tu tienda**: System → Settings (nombre, email, divisa, etc.).
2. **Añade productos**: Catalog → Products.
3. **Activa pagos y envíos**: Extensions → Extensions.
4. *(Opcional)* Activa las **SEO URLs**: System → Settings → Server → Enable SEO URLs. Las reglas de reescritura ya vienen incluidas en el Apache.

---

## Coste estimado

- **Capa gratuita / plan con crédito:** este despliegue usa **1 servicio + 1 volumen**, por lo que cabe holgado en el crédito mensual gratuito de un plan Hobby/desarrollo. Ideal para tiendas pequeñas o de prueba.
- El volumen de datos y el servicio activo consumen lo mínimo posible al usar un único contenedor.

Coste real según tráfico y tamaño de la base de datos — con una tienda pequeña estarás dentro de la cuota gratuita.

---

## Variables de entorno

La template funciona **sin configurar nada** (todos los valores tienen un defecto sensato). Puedes sobreescribirlos si quieres.

| Variable | Descripción | Default |
|----------|-------------|---------|
| `ADMIN_USERNAME` | Usuario del panel admin | `admin` |
| `ADMIN_PASSWORD` | Contraseña del admin | `opencart` |
| `ADMIN_EMAIL` | Email del admin | `admin@example.com` |
| `DB_PREFIX` | Prefijo de tablas de la BD | `oc_` |
| `HTTP_SERVER` | URL pública de la tienda (la pone Railway automáticamente con `RAILWAY_PUBLIC_DOMAIN`) | autodetectada |
| `MYSQLHOST` | Host de una BD externa (opcional, ver abajo) | embebida |
| `MYSQLPORT` | Puerto de la BD | `3306` |
| `MYSQLUSER` | Usuario de la BD | `opencart` |
| `MYSQLPASSWORD` | Contraseña de la BD | `opencart` |
| `MYSQLDATABASE` | Nombre de la BD | `opencart` |

### ¿Quieres usar una base de datos externa en vez de la embebida?
La template usa **MariaDB embebido** por defecto (cero configuración). Si ya tienes un servicio MySQL/MariaDB en Railway, solo tienes que definir `MYSQLHOST` (ej. `mysql.railway.internal`) y la template conectará con **esa** base en lugar de levantar la embebida. El resto de variables `MYSQL*` se usan para la conexión.

---

## Desarrollo local (Docker Compose)

```bash
git clone https://github.com/BURNI80/opencart-railway-template.git
cd opencart-railway-template
docker compose up -d --build
```

- **Tienda:** http://localhost:8080
- **Admin:** http://localhost:8080/admin/ (`admin` / `opencart`)

Para resetear todos los datos:
```bash
docker compose down -v
```

> Nota: en local usamos un MariaDB **separado** (servicio `mysql` de compose) para un flujo más cómodo. Los datos de BD se guardan en el volumen `mysql_data`, y el storage de OpenCart se guarda en volúmenes para `cache`, `logs`, `session`, `upload`, `download`, `modification` y `sass` (sin tapar `vendor`).

---

## Arquitectura

```
┌───────────────────────────────────────────┐
│          Contenedor OpenCart              │
│  ┌─────────────┐    ┌──────────────────┐  │
│  │  Apache 2.4  │◀──▶│   PHP 8.1        │  │
│  │  (prefork)   │    │  (gd, mysqli...) │  │
│  └─────────────┘    └──────────────────┘  │
│        └──────────────┬───────────────────┘
│                    OpenCart 4            │
│  ┌─────────────────────┐                 │
│  │  MariaDB embebido   │ 127.0.0.1:3306  │
│  └─────────────────────┘                 │
└───────────┬───────────────────────────────┘
            │
            ▼
   Volumen: /var/lib/mysql   ← datos de la BD (persistentes)
```

- **Apache escucha en `$PORT`** (Railway lo inyecta automáticamente) y el dominio público apunta a ese puerto.
- **`DIR_STORAGE = /var/www/html/system/storage/`** — IMPORTANTE: esta carpeta incluye el `vendor/` de Composer con el que OpenCart renderiza las plantillas (Twig). **No muevas storage fuera del document root**: rompería la tienda con `Class "Twig\Loader\FilesystemLoader" not found`.
- El entrypoint hace escribibles `/var/www` y el storage (owner `www-data`, permisos `775`) para que el panel admin no muestre el aviso de seguridad *"the folder /var/www/ need to be writable"*.

### Persistencia y el aviso de seguridad
- Los datos de la tienda (productos, pedidos, clientes, config) están en MariaDB → **volumen `/var/lib/mysql`**. Sobreviven a cada redeploy.
- El storage de OpenCart (`system/storage/`) vive dentro del contenedor y se regenera en cada arranque. Si necesitas persistir subidas/caché entre deploys, monta volúmenes en los subdirectorios concretos (no sobre `system/storage` completo).

---

## Solución de problemas

### El admin muestra el aviso "Warning: the folder /var/www/ need to be writable"
Es un **aviso de seguridad** de OpenCart, no un error. Esta template lo evita haciendo `/var/www` escribible (owner `www-data`, `chmod 775`) durante el arranque. No hagas caso a la recomendación de *mover* la carpeta storage fuera del document root: el `vendor/` de Composer vive dentro de `system/storage/vendor` y moverlo rompe la tienda.

### "Error: Class Twig\Loader\FilesystemLoader not found"
Sucede si `DIR_STORAGE` deja de apuntar a `system/storage/` (donde está `vendor/`). La template lo configura correctamente; no forces el storage a otra ruta.

### "Database Connection Failed"
- Solo pasa si configuraste `MYSQLHOST` externo y la conexión falló. Revisa host/puerto/usuario/contraseña.
- Con la BD embebida (por defecto) no debería ocurrir.

### 500 Internal Server Error
- Revisa los logs del deploy en el panel de Railway para ver el error PHP concreto.
- Comprueba que las variables de entorno no tengan valores rotos.

### SEO URLs / enlaces que dan 404
- Las reglas de reescritura de Apache ya están incluidas (`apache-opencart.conf`).
- Activa "SEO URLs" en System → Settings → Server y limpia la caché (icono de limpiar en el dashboard).

---

## Estructura del proyecto

```
├── Dockerfile              # Imagen PHP 8.1-Apache + MariaDB embebido
├── docker-entrypoint.sh    # Arranca BD, instala OpenCart, configura Apache
├── install.php             # Instalador idempotente (esquema + datos + admin)
├── apache-opencart.conf    # VirtualHost con reglas de reescritura (SEO)
├── docker-compose.yml      # Para desarrollo local
├── .env.example            # Variables de entorno de referencia
└── README.md               # Esta documentación
```

---

## Licencia

GPL v2 — igual que [OpenCart](https://github.com/opencart/opencart/blob/master/LICENSE.md).
