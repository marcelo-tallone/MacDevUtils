# MacDevUtils

Conjunto de herramientas de desarrollo para macOS, construido nativamente con Swift y SwiftUI. Una aplicacion liviana y sin dependencias externas, pensada para desarrolladores que necesitan utilidades rapidas del dia a dia.

## Funcionalidades

### Conversor
Convierte texto entre multiples formatos de codificacion:
- ASCII, HEX, Base64, Binario, Decimal
- URL Encode / Decode
- HTML Entities
- UTF-8 Bytes

Permite convertir de cualquier formato a cualquier otro de forma instantanea.

### Editor
Editor de texto con multiples pestanas, similar a Notepad++:
- **Pestanas**: abrir, cerrar y navegar entre multiples archivos
- **Abrir/Guardar**: soporte para cualquier tipo de archivo de texto (Cmd+O, Cmd+S, Cmd+Shift+S)
- **Syntax highlighting**: JSON, XML, HTML, SQL, CSS y texto plano
- **Buscar y Reemplazar**: Cmd+F / Cmd+H con opciones de busqueda:
  - Distinguir mayusculas/minusculas
  - Palabra completa
  - Expresion regular
- **Ajuste de linea**: activar/desactivar word wrap
- **Numeros de linea**
- **Barra de estado**: linea/columna del cursor, cantidad de caracteres, lineas, lenguaje y encoding

### Validador
Valida y formatea multiples tipos de datos:
- **JSON**: validacion con mensajes de error precisos (linea y columna), formateo que preserva el orden original de los campos
- **XML**: validacion y pretty-print
- **HTML**: validacion y formateo
- **YAML**: validacion basica (indentacion, comillas, tabs)
- **SQL**: validacion de parentesis y comillas, formateo con keywords en mayusculas
- **HEX**: validacion de caracteres y formato en bloques
- **ASCII**: deteccion de caracteres no-ASCII
- **BLOB**: volcado hexadecimal con vista ASCII

### Comparador
Comparacion de textos lado a lado con deteccion de diferencias:
- Algoritmo LCS (Longest Common Subsequence) para deteccion precisa de cambios
- **Resaltado inline**: dentro de las lineas modificadas, resalta los caracteres especificos que cambiaron
- **Colores**: verde (agregado), rojo (eliminado), naranja (modificado), sin color (igual)
- **Emparejamiento inteligente**: solo marca como "modificada" lineas que tienen similitud real (>40%)
- Estadisticas de diferencias
- Cargar archivos desde disco o pegar texto directamente
- Boton para intercambiar los textos

### Buscador
Busqueda avanzada de archivos, similar a "Find in Files" de Notepad++:
- **Buscar en contenido**: busca texto dentro de archivos, mostrando linea y contexto
- **Buscar por nombre**: busca archivos por nombre, con soporte para wildcards (* y ?)
- **Directorio raiz**: buscar en toda la Mac o elegir una carpeta especifica
- **Filtro de archivos**: filtrar por extension (ej: *.json, *.xml)
- **Opciones**: distinguir mayusculas, palabra completa, expresion regular
- Salto automatico de archivos binarios (imagenes, videos, compilados, etc.)
- Doble click en un resultado para abrir el archivo en el Editor
- Boton de cancelar para detener busquedas largas
- Limite de 5000 resultados para proteger la memoria

## Requisitos

- **macOS 12.0 (Monterey)** o superior
- **Xcode Command Line Tools** instalados (para el compilador `swiftc`)
- Arquitectura **Intel (x86_64)** o **Apple Silicon (arm64)**

### Importante

- **Solo funciona en macOS**. No es compatible con Windows, Linux ni ningun otro sistema operativo.
- La aplicacion usa frameworks nativos de Apple (AppKit, SwiftUI) que solo existen en macOS.
- No requiere Xcode completo, solo las Command Line Tools.

## Instalacion

### 1. Clonar el repositorio

```bash
git clone https://github.com/marcelo-tallone/MacDevUtils.git
cd MacDevUtils
```

### 2. Instalar Xcode Command Line Tools (si no las tenes)

```bash
xcode-select --install
```

### 3. Compilar

```bash
cd MacDevUtils
bash build.sh
```

Esto genera la aplicacion en `build/MacDevUtils.app`.

### 4. Instalar (opcional)

Para copiar la app a la carpeta de Aplicaciones:

```bash
cp -r build/MacDevUtils.app /Applications/
```

Una vez instalada, MacDevUtils aparece en el Launchpad y tambien en el menu "Abrir con" del Finder para archivos de texto, JSON, XML, HTML, SQL, CSS y YAML.

### 5. Ejecutar sin instalar

Tambien podes ejecutar la app directamente desde donde se compilo:

```bash
open build/MacDevUtils.app
```

## Estructura del proyecto

```
MacDevUtils/
  main.swift          # Entry point, AppDelegate, menu principal
  ContentView.swift   # Vista principal, sidebar, navegacion entre herramientas
  CodeEditor.swift    # Componente de editor con syntax highlighting y numeros de linea
  ConverterView.swift # Herramienta de conversion entre formatos
  EditorView.swift    # Editor de texto con pestanas
  ValidatorView.swift # Validador y formateador
  CompareView.swift   # Comparador de textos con diff
  SearchView.swift    # Buscador de archivos
  Info.plist          # Configuracion de la app (tipos de archivo soportados, etc.)
  create_icon.swift   # Generador del icono de la aplicacion
  build.sh            # Script de compilacion
```

## Tecnologias

- **Swift** (compilado directamente con `swiftc`, sin Xcode project)
- **SwiftUI** para la interfaz de usuario
- **AppKit** para integracion nativa con macOS (NSTextView, panels, menus)
- Sin dependencias externas ni package managers

## Licencia

Este proyecto es de uso libre.
