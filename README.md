# IPTV

Cliente nativo de iOS para reproducir contenido de servidores **Xtream Codes**. La app permite ver canales en directo, películas bajo demanda (VOD) y series con episodios organizados por temporadas.

Interfaz en modo oscuro con efectos Liquid Glass, reproductor basado en **libVLC** (VLCKit) y caché local para catálogos grandes.

## Características

### Contenido
- **Live TV** — Canales en directo agrupados por categorías, con vista de todos los canales y búsqueda.
- **Películas** — Catálogo VOD con miniaturas y búsqueda.
- **Series** — Listado de series con detalle por temporadas y episodios.

### Reproductor
- Reproducción con **VLCKit 4.0** (libVLC): HLS (`.m3u8`), MPEG-TS (`.ts`) y códecs habituales en IPTV.
- Fallback automático entre formatos TS y HLS en directo si uno falla.
- Modo pantalla completa con rotación a landscape.
- **Picture in Picture** al pasar la app a segundo plano en pantalla completa.
- Controles VOD: play/pause, avance/retroceso de 10 s y barra de progreso.
- Reconexión automática ante cortes de red (hasta 5 intentos).

### Experiencia de uso
- Sesión persistente: las credenciales se guardan en el **Keychain** del dispositivo.
- Caché en disco de playlists (Live TV, películas y series) para arranque rápido sin red.
- Miniaturas con caché en memoria y descarga optimizada para listas muy largas.
- Pull-to-refresh y botón de actualización en cada sección.
- UI en español con búsqueda integrada (`searchable`).

## Requisitos

| Requisito | Versión |
|-----------|---------|
| Xcode | 26.5+ |
| iOS | 26.5+ |
| Swift | 5.0 |
| Dispositivos | iPhone e iPad |

## Instalación

1. Clona o abre el repositorio en tu Mac.
2. Abre `iptv.xcodeproj` en Xcode.
3. Xcode resolverá automáticamente la dependencia **VLCKitSPM** vía Swift Package Manager.
4. Selecciona tu equipo de desarrollo en *Signing & Capabilities*.
5. Compila y ejecuta en simulador o dispositivo físico (`⌘R`).

> **Nota:** La app usa `NSAllowsArbitraryLoads` para conectar con servidores IPTV que suelen ser HTTP. En producción conviene restringir excepciones ATS a dominios concretos.

## Uso

1. Al abrir la app, introduce la **URL del servidor**, **usuario** y **contraseña** de tu proveedor Xtream Codes.
2. Tras autenticarse, accede a **Live TV**, **Movies** o **Series** desde la pantalla principal.
3. Toca un canal, película o episodio para abrir el reproductor.
4. En el reproductor, usa el botón de expandir para pantalla completa; al salir de la app en ese modo se activa PiP si está disponible.
5. Para cerrar sesión, pulsa el icono de salida en la barra superior de la pantalla principal.

### Formato de URL del servidor

Introduce la URL base de tu panel Xtream, por ejemplo:

```
http://ejemplo.com:8080
```

La app construye las peticiones a `player_api.php` y las URLs de stream automáticamente.

## Arquitectura

```
iptv/
├── Models/           # Modelos Codable (Xtream API, PlayableItem, MediaSection)
├── Services/         # XtreamAPIService, CredentialStore (Keychain)
├── ViewModels/       # SessionManager, stores de catálogo, PlaybackController
├── Views/            # SwiftUI (Login, Home, listas, reproductor)
├── Assets.xcassets/
└── iptvApp.swift     # Punto de entrada, AppDelegate (orientación, audio)
```

### Capas principales

| Componente | Responsabilidad |
|------------|-----------------|
| `SessionManager` | Login/logout, persistencia de credenciales, configuración del API |
| `XtreamAPIService` | Autenticación y endpoints Xtream (`get_live_streams`, `get_vod_streams`, `get_series`, etc.) |
| `CredentialStore` | Almacenamiento seguro en Keychain (`com.javieralarcn10.iptv`) |
| `LivePlaylistStore` / `MovieStore` / `SeriesStore` | Carga, caché en disco y refresco de catálogos |
| `PlaybackController` | Wrapper de VLCMediaPlayer: PiP, reconexión, seek, watchdog |
| `ThumbnailCache` | Descarga y downsampling de miniaturas con límite de memoria |

### Flujo de datos

```
LoginView → SessionManager → XtreamAPIService → Servidor Xtream
                ↓
           CredentialStore (Keychain)
                ↓
HomeView → Stores (caché disco + red) → Vistas de listado → PlayerView → PlaybackController (VLCKit)
```

### Decisiones técnicas relevantes

- **`@Observable`** (Observation) en lugar de Combine/`ObservableObject` para estado reactivo.
- El `VLCMediaPlayer` se crea de forma **perezosa** en `prepare()`, no en `init`, porque SwiftUI instancia destinos de `NavigationLink` de forma anticipada.
- Live TV prioriza extensión `.ts` sobre `.m3u8` por compatibilidad con proveedores IPTV; el reproductor puede alternar si falla.
- Los catálogos se guardan en `Documents/` para que iOS no los purgue como caché temporal.

## Dependencias

| Paquete | Origen | Uso |
|---------|--------|-----|
| [VLCKitSPM](https://github.com/virtualox/vlckit-spm) | Swift Package Manager | Reproducción de video (libVLC 4.0) |

## API Xtream Codes

La app implementa los endpoints habituales de la API de reproductor Xtream:

| Acción | Uso |
|--------|-----|
| *(auth)* | Validación de credenciales |
| `get_live_categories` / `get_live_streams` | Live TV |
| `get_vod_streams` | Películas |
| `get_series` / `get_series_info` | Series y episodios |

URLs de reproducción:

```
{server}/live/{user}/{pass}/{stream_id}.{ext}
{server}/movie/{user}/{pass}/{stream_id}.{ext}
{server}/series/{user}/{pass}/{episode_id}.{ext}
```

## Licencia

Proyecto privado. Uso bajo tu propia responsabilidad y cumpliendo la legislación aplicable sobre streaming y derechos de autor.

---

**Bundle ID:** `com.javieralarcn10.iptv` · **Versión:** 1.0
