# jira-edit(1) -- Edición granular de campos en issues

## SINTAXIS
`jira [ISSUE_KEY] --data` <jsonfile|jsoncontent>  
`jira edit` <ISSUE_KEY> [opciones]  
`jira issue edit` <ISSUE_KEY> [opciones]  

## DESCRIPCIÓN
Modifica campos específicos de un ticket existente (resumen, descripción, prioridad, asignación, etiquetas y componentes) de forma atómica y sin tener que construir JSON a mano, o actualiza el issue directamente usando `--data` con un archivo JSON, entrada estándar (`-`) o contenido JSON en línea.

En Jira Cloud (v3), la descripción se convierte automáticamente de Markdown a ADF. Con `--data`, los formatos JSON planos (sin `fields`) se envuelven y normalizan automáticamente.

## OPCIONES
* `--data` <jsonfile|jsoncontent|->:
  Actualiza el ticket con payload JSON directo, ruta a archivo JSON o entrada estándar (`-`). Acepta estructura nativa (`{"fields":{...}}`) o formato plano (`{"summary":"..."}`).
* `-s`, `--summary` <texto>:
  Nuevo título/resumen del ticket.
* `-d`, `--description` <texto>:
  Nueva descripción (soporta Markdown). Usa `-` para leer desde stdin.
* `--description-file` <ruta>:
  Lee la descripción desde un archivo Markdown/texto.
* `-P`, `--priority` <nombre>:
  Nueva prioridad (High, Medium, Low, etc.).
* `-a`, `--assignee` <usuario|email|me|none>:
  Asignar ticket a un usuario o desasignar (`none`).
* `--add-label` <etiquetas>:
  Agrega etiquetas separadas por comas (`--add-label backend,v2`).
* `--remove-label` <etiquetas>:
  Elimina etiquetas separadas por comas.
* `--add-component` <componentes>:
  Agrega componentes al ticket.
* `--remove-component` <componentes>:
  Elimina componentes del ticket.
* `-f`, `--field` key=value:
  Modifica un campo personalizado directo.
* `--dry-run`:
  Muestra el payload generado sin enviarlo a Jira.
* `-h`, `--help`:
  Muestra esta ayuda.

## EJEMPLOS
```bash
# Actualizar ticket directamente con JSON en línea
jira PROJ-123 --data '{"summary": "Nuevo título", "priority": "High"}'

# Actualizar ticket desde archivo JSON
jira PROJ-123 --data ./update.json

# Actualizar ticket desde pipe (stdin)
cat update.json | jira PROJ-123 --data -

# Cambiar título y prioridad con flags
jira edit PROJ-123 --summary "Nuevo título refinado" --priority High

# Actualizar descripción desde archivo Markdown
jira issue edit PROJ-123 --description-file ./docs/spec.md

# Agregar y remover etiquetas de forma atómica
jira edit PROJ-123 --add-label "backend,api" --remove-label "legacy"

# Asignar a uno mismo
jira edit PROJ-123 --assignee me
```

