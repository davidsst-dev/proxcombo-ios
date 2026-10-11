# ProX Combo — versión iPhone (iOS)

App para iPhone con las mismas funciones que la app Android: recibe las piernas de una
combinada, consulta el precio actual de cada pierna en la API pública de Kalshi,
recalcula la ventaja, crea la combinada en Kalshi con la API key del usuario y abre
la app de Kalshi en esa combinada. **El usuario aprueba la apuesta dentro de Kalshi;
esta app NUNCA coloca órdenes.**

La app NO analiza nada y NO usa ninguna IA: los pronósticos los genera otro sistema
cada mañana.

## Funciones

- **Pegar combinada** (texto o portapapeles) con validación idéntica a Android
  (máx. 6 piernas, `TICKER~EVENT_TICKER~LADO~PROB`, o solo el ticker).
- **Revisión**: precio actual por pierna, probabilidad, ventaja en pts, totales
  (precio, probabilidad, ventaja, "Paga ×"), alertas con segundo toque de
  confirmación, botón "Refrescar" y "Compartir".
- **Crear combinada** (firmada SHA256withRSA/PSS) o abrir pierna sencilla.
- **Historial** (últimas 10) con selección, eliminar seleccionadas, limpiar todo,
  copiar códigos y compartir.
- **Ajustes**: Key ID + llave PEM (en **Keychain**), base URL, colección, URL de
  pronósticos, umbrales de ventaja, "Probar Kalshi" y "Borrar todas las claves".
- **Bloqueo biométrico** (Face ID / Touch ID) al abrir y al volver tras 5 min en
  segundo plano.
- **Seguridad**: solo dos rutas permitidas (allowlist), solo HTTPS, llaves solo en
  Keychain, sin código para `/portfolio`, `/orders`, `/communications`, `/api_keys`
  ni ningún otro endpoint.

## Stack

- Swift 5.10 · SwiftUI · iOS 16+
- URLSession (async/await) · Security framework (firma PSS + Keychain)
- XcodeGen (genera el proyecto en la CI) · GitHub Actions (compila gratis)

---

# Cómo compilar e instalar (ruta GRATIS, sin Mac)

La compilación se hace en los servidores de macOS de **GitHub Actions** (gratis en
repositorios públicos). La instalación se hace con **Sideloadly** (o AltStore) desde
tu Windows, usando tu cuenta de Apple gratuita.

## Paso 1 — Subir el código a GitHub

1. Crea una cuenta en [github.com](https://github.com) si no la tienes.
2. Crea un **repositorio nuevo y PÚBLICO** (p. ej. `proxcombo-ios`).
   - Público = minutos de macOS **ilimitados** (gratis).
3. Sube **toda la carpeta** de este proyecto al repositorio (arrastrando los archivos
   por la web, o con `git`). Debe quedar así en la raíz del repositorio:
   ```
   project.yml
   .github/workflows/build.yml
   ProXCombo/...
   README.md
   ```

## Paso 2 — Compilar en GitHub Actions

1. Ve a tu repositorio → pestaña **Actions**.
2. La primera vez, haz clic en **"Build ProXCombo iOS"** → **"Run workflow"**.
   (En pushes a `main` se lanza sola.)
3. Espera ~3–6 minutos. Cuando el check esté en verde, abre la ejecución.
4. Abajo verás el artefacto **`ProXCombo`** → descárgalo. Es un `.zip` con
   **`ProXCombo.ipa`** dentro. Descomprímelo.

> Si la compilación falla, abre los logs del paso que falló y compártelos para
> corregirlo.

## Paso 3 — Instalar en el iPhone con Sideloadly

1. En tu Windows, descarga e instala **Sideloadly** (sideloadly.io).
2. Conecta el iPhone por USB (o Wi-Fi) y ábrelo.
3. En Sideloadly, arrastra el **`ProXCombo.ipa`** a la ventana.
4. Escribe tu **ID de Apple** (el mismo de tu iPhone) y la contraseña. Acepta los
   términos.
5. Pulsa **Start**. Sideloadly re-firma la app con tu cuenta y la instala.
   - El iPhone pedirá "Confiar en la app" → Ajustes > General > VPN y
     dispositivos → confía en tu perfil.
6. Listo: la app **ProX Combo** aparece en tu iPhone.

> **Caducidad:** con cuenta de Apple gratuita la app caduca a los **7 días**.
> Para renovarla, repite el Paso 3 con el mismo `.ipa` (o recompila). Si quieres
> 90 días por build, la opción es Apple Developer ($99/año) + TestFlight.

## Paso 4 — Configurar la app

1. Abre ProX Combo y desbloquéala con Face ID / Touch ID.
2. Ve a **Ajustes** y pega la **Key ID** y la **llave privada (PEM)**.
3. Pulsa **"Probar Kalshi"**:
   - "Conexión correcta" = Kalshi aceptó tu firma (key y llave válidas).
   - "Credenciales incorrectas" = revisa la Key ID y la llave.
4. Ya puedes usar **"Pegar combinada"** en el Inicio.

## Seguridad

- Key ID y llave privada **solo** en el **Keychain** (nunca en UserDefaults, logs,
  excepciones ni portapapeles). En pantalla se muestran como `••••` + últimos 4.
- `Allowlist`: se rechaza, sin enviar, cualquier petición fuera de
  `GET /trade-api/v2/markets/{ticker}` y
  `POST /trade-api/v2/multivariate_event_collections/{colección}` sobre
  `api.elections.kalshi.com` / `external-api.kalshi.com`, solo HTTPS.
- Sin código para `/portfolio`, `/orders`, `/communications`, `/api_keys` ni ningún
  otro endpoint.
- Reintento exponencial ante 429/5xx (1 s, 2 s, 4 s). Errores en español.

## Notas

- El identificador de la app es `com.proxcombo.ios` (distinto del Android
  `com.proxcombo.app`), así no hay conflicto entre plataformas.
- Si pierdes el iPhone, **borra la API key desde la web de Kalshi**: así queda
  invalidada aunque el dispositivo caiga en malas manos.
