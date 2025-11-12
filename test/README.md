# Tests

Este directorio contiene las pruebas unitarias para jira-cli.sh.

## Requisitos

Se requiere el framework [shellunittest](https://github.com/caherrera/shellunittest) para ejecutar las pruebas.

## Ejecutar las pruebas

```bash
# Desde el directorio raíz del proyecto
shellunittest test/

# O usar el script wrapper
./test/run_all_tests.sh
```

## Estructura de Tests

- `test_helpers.sh` - Pruebas para las funciones de helpers.sh
  - Funciones de logging (info, error, warn, success, debug)
  - Funciones de color
  - Verificación de que los logs van a stderr
  - Funciones de formato (split_title, printtitle)

- `test_md2jira.sh` - Pruebas para el conversor md2jira
  - Conversión Markdown → Wiki Markup
  - Conversión Markdown → ADF (JSON)
  - Autodetección de formato
  - Múltiples métodos de input (file, pipe, stdin)
  - Manejo de errores

- `test_help.sh` - Pruebas para validar flags de ayuda
  - Verifica que `-h` y `--help` funcionen en todos los comandos
  - Prueba el comando principal `jira` y todos sus subcomandos
  - Prueba scripts independientes (jira-issue.sh, jira-search.sh, etc.)
  - Prueba binarios en el directorio `bin/`
  - Incluye 50+ tests de validación

## Añadir nuevas pruebas

Para crear un nuevo archivo de pruebas:

1. Crear un archivo `test_*.sh` en este directorio
2. Usar el siguiente template:

```bash
#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# Source the testing framework
source "/Users/carlosherrera/src/carlos/caherrera/shellunittest/src/unittest.sh"

initialize_test_framework "$@"

print_test_header "Mi Suite de Tests"

print_section "Sección de Tests"

# Tus pruebas aquí
assert_equals "expected" "actual" "descripción del test"

print_summary
```

3. Hacer el archivo ejecutable: `chmod +x test_*.sh`

## Assertions Disponibles

- `assert_equals "expected" "actual" "message"` - Verifica igualdad
- `assert_contains "haystack" "needle" "message"` - Verifica que contiene
- `assert_success "message"` - Verifica exit code 0
- `assert_exit_code expected actual "message"` - Verifica exit code específico
- `assert_file_exists "path" "message"` - Verifica que archivo existe
- `assert_file_contains "path" "text" "message"` - Verifica contenido de archivo
- `assert_file_not_contains "path" "text" "message"` - Verifica ausencia de texto

## CI/CD

Los tests pueden ejecutarse en CI usando:

```bash
shellunittest test/ --format=junit > test-results.xml
```

O en formato JSON:

```bash
shellunittest test/ --format=json > test-results.json
```
