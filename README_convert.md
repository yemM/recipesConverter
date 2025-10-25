# Cooklang to Markdown Converter

This script converts cooklang files to markdown format following the template.md structure.

## Usage

```bash
./convert_cooklang.sh <source_folder> <destination_folder>
```

## Examples

```bash
# Convert all recipes from examples folder to converted_recipes folder
./convert_cooklang.sh examples converted_recipes

# Convert only appetizers
./convert_cooklang.sh examples/Apéritifs converted_appetizers
```

## Features

- Automatically extracts ingredients from `@ingredient{quantity}` syntax
- Extracts equipment from `#equipment{}` syntax  
- Converts recipe steps while replacing ingredient/equipment markers with placeholders
- Finds associated image files (png, jpg, jpeg, heic) with the same base name
- Preserves directory structure in the output
- Handles missing ingredients, equipment, or steps gracefully

## Output Format

The script generates markdown files following this structure:

```markdown
# Recipe Title

![image](image_filename)

## Ingrédients

- ingredient1 : quantity1
- ingredient2 : quantity2

## Matériel

- equipment1
- equipment2

## Étapes

Step 1 with [ingredient] and [equipment] placeholders
Step 2...
```

## Requirements

- Bash shell
- Python 3 (for cross-platform path handling)
- Standard Unix tools (find, grep, sed, etc.)
