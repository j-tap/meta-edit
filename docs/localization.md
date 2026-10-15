# Localization

## Languages

| Code | Language |
|---|---|
| `en` | English, the source language and the fallback |
| `ru` | Russian |
| `es` | Spanish |
| `zh-Hans` | Chinese, Simplified |

## Choosing the language

- By default the app follows the system: the first of the user's preferred languages that the app supports,
  matched the way the platform does it (`ru-ES` gives Russian, `es-419` Spanish, `zh-Hans-CN` Chinese).
  Without a match the app uses English.
- Settings has a Language picker: "System" plus every supported language, each named in its own language.
  The choice is stored per user and applies at once to everything the app draws itself.
- Menus and dialogs that the platform provides (on macOS: Edit, Window, Services, the app menu) follow the
  chosen language after a restart. The app tells the user so under the picker.

## Rules

- Every string the user sees is translated: field labels, group titles, menus, buttons, tooltips, status
  messages, confirmations and error messages.
- Not translated: tag names in All tags (they are identifiers such as `TITLE` or `dc:title`), values read from
  files, file names, units that are the same everywhere (BPM, ISRC, GPS).
- Counts use the plural rules of the language: Russian has one / few / many (1 файл, 2 файла, 5 файлов),
  English and Spanish one / other, Chinese a single form.
- Dates follow the chosen language.
- A missing translation falls back to English. Each app has a test that fails when a language lacks a key.

## Glossary

Field names the three apps must use. File group names follow what the platform file manager shows.

| key | English | Russian | Spanish | Chinese |
|---|---|---|---|---|
| group general | General | Основное | General | 常规 |
| group audio | Audio | Аудио | Audio | 音频 |
| group photo | Photo | Фото | Foto | 照片 |
| group video | Video | Видео | Vídeo | 视频 |
| group file | File | Файл | Archivo | 文件 |
| group technical | Technical | Технические данные | Datos técnicos | 技术信息 |
| group raw | All tags | Все теги | Todas las etiquetas | 全部标签 |
| title | Title | Название | Título | 标题 |
| artist (audio) | Artist | Исполнитель | Artista | 艺人 |
| artist (video, image) | Author | Автор | Autor | 作者 |
| album | Album | Альбом | Álbum | 专辑 |
| albumArtist | Album artist | Исполнитель альбома | Artista del álbum | 专辑艺人 |
| date (audio) | Year | Год | Año | 年份 |
| date (video) | Date | Дата | Fecha | 日期 |
| date (image) | Date created | Дата создания | Fecha de creación | 创建日期 |
| genre | Genre | Жанр | Género | 类型 |
| track | Track | Трек | Pista | 音轨 |
| disc | Disc | Диск | Disco | 光盘 |
| composer | Composer | Композитор | Compositor | 作曲 |
| comment | Comment | Комментарий | Comentario | 注释 |
| description | Description | Описание | Descripción | 描述 |
| keywords | Keywords | Ключевые слова | Palabras clave | 关键词 |
| copyright | Copyright | Авторские права | Copyright | 版权 |
| rating | Rating | Рейтинг | Valoración | 评分 |
| cover | Cover | Обложка | Portada | 封面 |
| name | Name | Имя | Nombre | 名称 |
| tags | Tags | Теги | Etiquetas | 标签 |
| whereFrom | Where from | Откуда | Procedencia | 来源网址 |
| created | Created | Создан | Creado | 创建时间 |
| modified | Modified | Изменён | Modificado | 修改时间 |

The full list of strings lives in each app: `apps/macos/Sources/MetaEdit/Localization/`.
