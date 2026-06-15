# IPTV

Cliente nativo de iOS para ver contenido de servidores **Xtream Codes**. La app soporta canales en directo, películas bajo demanda y series, con una interfaz oscura y reproducción basada en **VLCKit**.

## Funcionalidades

- **Live TV** con categorías, lista completa y búsqueda.
- **Películas** con catálogo VOD y miniaturas.
- **Series** con temporadas y episodios.
- Reproducción de **HLS** (`.m3u8`) y **MPEG-TS** (`.ts`).
- Modo pantalla completa, **Picture in Picture** y reconexión automática.
- Sesión persistente con credenciales guardadas en **Keychain**.
- Caché local para cargar catálogos y miniaturas más rápido.

## Requisitos

- **Xcode** 26.5 o superior
- **iOS** 26.5 o superior
- **Swift** 5.0
- Compatible con **iPhone** y **iPad**

## Instalación

1. Abre el repositorio en Xcode.
2. Abre `iptv.xcodeproj`.
3. Xcode descargará automáticamente `VLCKitSPM` con Swift Package Manager.
4. Configura tu equipo en *Signing & Capabilities*.
5. Compila y ejecuta con `⌘R`.

## Uso

1. Introduce la **URL del servidor**, **usuario** y **contraseña** de tu proveedor Xtream.
2. Accede a **Live TV**, **Movies** o **Series** desde la pantalla principal.
3. Toca un elemento para abrir el reproductor.
4. Usa el botón de pantalla completa para cambiar a paisaje y activar PiP si está disponible.
5. Para cerrar sesión, usa el botón de salida en la barra superior.

### URL del servidor

Introduce solo la URL base del panel, por ejemplo:

```text
http://ejemplo.com:8080
```

La app construye automáticamente las llamadas a `player_api.php` y las URLs de reproducción.

## Dependencias

- [VLCKitSPM](https://github.com/virtualox/vlckit-spm) para la reproducción de video con libVLC 4.0.

## Estructura

```text
iptv/
├── Models/
├── Services/
├── ViewModels/
├── Views/
├── Assets.xcassets/
└── iptvApp.swift
```

## API Xtream Codes

La app usa los endpoints habituales de Xtream:

- `get_live_categories` y `get_live_streams` para Live TV
- `get_vod_streams` para películas
- `get_series` y `get_series_info` para series

URLs de reproducción:

```text
{server}/live/{user}/{pass}/{stream_id}.{ext}
{server}/movie/{user}/{pass}/{stream_id}.{ext}
{server}/series/{user}/{pass}/{episode_id}.{ext}
```

## Licencia

Proyecto privado. Úsalo bajo tu propia responsabilidad y cumpliendo la legislación aplicable sobre streaming y derechos de autor.

**Bundle ID:** `com.javieralarcn10.iptv` · **Versión:** 1.0
