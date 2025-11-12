# Uso de archivos JSON para crear issues

El script `jira-create-issue` ahora soporta la lectura de propiedades desde archivos JSON. Esto permite preparar la información del issue en un archivo y crear el ticket de forma más conveniente.

## Formato del archivo JSON

El archivo JSON puede contener las siguientes propiedades:

```json
{
  "project": "CLAVE_PROYECTO",
  "type": "Bug",
  "summary": "Título del issue",
  "description": "Descripción detallada del issue",
  "priority": "High",
  "assignee": "nombre.usuario",
  "reporter": "nombre.reporter",
  "epic": "EPIC-123",
  "link": "ISSUE-456"
}
```

### Propiedades soportadas:

- **project**: Clave del proyecto en Jira
- **type**: Tipo de issue (Bug, Task, Story, etc.)
- **summary**: Título o resumen del issue (requerido)
- **description**: Descripción detallada del issue
- **priority**: Prioridad (High, Medium, Low, etc.)
- **assignee**: Usuario asignado
- **reporter**: Usuario reportero
- **epic**: Clave del Epic al que se vincula
- **link**: Clave de otro issue para crear un link "Relates to"

## Ejemplos de uso

### 1. Crear issue desde archivo JSON
```bash
jira-create-issue issue.json
```
Lee todas las propiedades del archivo `issue.json` y pregunta por las que falten.

### 2. Crear issue con override del tipo
```bash
jira-create-issue issue.json --type=Soporte
```
Lee las propiedades del archivo pero usa "Soporte" como tipo de issue, ignorando el valor en el JSON.

### 3. Combinar archivo JSON con otras opciones
```bash
jira-create-issue issue.json --priority=Critical --assignee=otro.usuario
```
Los parámetros de línea de comandos siempre tienen prioridad sobre los valores del JSON.

## Comportamiento

1. **Prioridad de valores**: Los parámetros de línea de comandos siempre sobrescriben los valores del archivo JSON.

2. **Campos requeridos**: Si faltan los campos requeridos (project, type, summary), el script preguntará interactivamente por ellos.

3. **Campos opcionales**: Los campos opcionales (description, assignee, priority, etc.) se usan si están en el JSON, pero no se pregunta por ellos si faltan.

## Ejemplo de archivo JSON completo

Archivo: `example-issue.json`
```json
{
  "project": "MYPROJECT",
  "type": "Bug",
  "summary": "Error en el login del sistema",
  "description": "Cuando un usuario intenta iniciar sesión, aparece un error 500 en el servidor.\n\nPasos para reproducir:\n1. Ir a la página de login\n2. Ingresar credenciales válidas\n3. Hacer clic en 'Iniciar Sesión'\n\nResultado esperado: El usuario debería poder acceder al sistema\nResultado actual: Se muestra un error 500",
  "priority": "High",
  "assignee": "john.doe"
}
```

## Compatibilidad con formato Jira API

El script también soporta el formato estándar de la API de Jira:

```json
{
  "fields": {
    "project": { "key": "MYPROJECT" },
    "issuetype": { "name": "Bug" },
    "summary": "Título del issue",
    "description": "Descripción",
    "priority": { "name": "High" },
    "assignee": { "name": "john.doe" }
  }
}
```
