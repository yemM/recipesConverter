#!/bin/bash

# Script to convert cooklang files to markdown format
# Usage: ./convert_cooklang.sh <source_folder> <destination_folder> [export_format]

# Check if correct number of arguments provided
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Usage: $0 <source_folder> <destination_folder> [export_format]"
    echo "Example: $0 ./examples ./converted_recipes"
    echo "Example: $0 ./examples ./converted_recipes pdf"
    echo "Example: $0 ./examples ./converted_recipes html"
    echo "Supported formats: pdf, html, docx, epub, etc. (requires pandoc)"
    exit 1
fi

SOURCE_FOLDER="$1"
DEST_FOLDER="$2"
EXPORT_FORMAT="$3"

# Check if source folder exists
if [ ! -d "$SOURCE_FOLDER" ]; then
    echo "Error: Source folder '$SOURCE_FOLDER' does not exist"
    exit 1
fi

# Create destination folder if it doesn't exist
mkdir -p "$DEST_FOLDER"

# Function to extract recipe title from filename
get_recipe_title() {
    local filename="$1"
    # Remove .cook extension and replace underscores with spaces
    basename "$filename" .cook | sed 's/_/ /g'
}

# Function to extract servings from cooklang content
extract_servings() {
    local content="$1"
    # Extract servings from metadata lines and clean up any line breaks
    echo "$content" | grep '^>> servings:' | sed 's/^>> servings: *//' | tr -d '\n\r'
}

# Function to extract source from cooklang content
extract_source() {
    local content="$1"
    # Extract source from metadata lines and clean up any line breaks
    echo "$content" | grep '^>> source:' | sed 's/^>> source: *//' | tr -d '\n\r'
}

# Function to extract ingredients from cooklang content
extract_ingredients() {
    local content="$1"
    # Extract ingredients (lines starting with @)
    echo "$content" | grep -o '@[^{]*{[^}]*}' | while read -r ingredient; do
        # Remove @ and extract name and quantity
        name=$(echo "$ingredient" | sed 's/@\([^{]*\){.*/\1/')
        quantity=$(echo "$ingredient" | sed 's/@[^{]*{\([^}]*\)}/\1/')
        # Clean up % symbols in quantity - replace % with space
        quantity=$(echo "$quantity" | sed 's/%/ /g')
        echo "- $name : $quantity"
    done | sort -u
}

# Function to extract equipment from cooklang content
extract_equipment() {
    local content="$1"
    # Extract equipment (lines starting with #)
    echo "$content" | grep -o '#[^{]*{[^}]*}' | while read -r equipment; do
        # Remove # and extract name
        name=$(echo "$equipment" | sed 's/#\([^{]*\){.*/\1/')
        echo "- $name"
    done | sort -u
}

# Function to extract steps from cooklang content
extract_steps() {
    local content="$1"
    # Remove metadata lines (starting with >>) and empty lines
    # Keep ingredient and equipment names but remove the markers and quantities
    # Convert to numbered list
    local step_num=1
    echo "$content" | grep -v '^>>' | grep -v '^$' | sed 's/@\([^{]*\){[^}]*}/\1/g' | sed 's/#\([^{]*\){[^}]*}/\1/g' | while read -r line; do
        # Trim whitespace and only process non-empty lines
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$line" ]; then
            echo "$step_num. $line"
            step_num=$((step_num + 1))
        fi
    done
}

# Function to find associated image file
find_image() {
    local cook_file="$1"
    local base_name=$(basename "$cook_file" .cook)
    local dir_name=$(dirname "$cook_file")
    
    # Look for common image extensions
    for ext in png jpg jpeg PNG JPG JPEG heic HEIC; do
        if [ -f "$dir_name/$base_name.$ext" ]; then
            echo "$base_name.$ext"
            return
        fi
    done
    
    # If no image found, return placeholder
    echo "no-image.png"
}

# Function to convert markdown to specified format using pandoc
convert_to_format() {
    local md_file="$1"
    local format="$2"
    local output_file="${md_file%.md}.${format}"
    
    # Check if pandoc is available
    if ! command -v pandoc &> /dev/null; then
        echo "Warning: pandoc is not installed. Cannot convert to $format format."
        echo "Please install pandoc: https://pandoc.org/installing.html"
        return 1
    fi
    
    # Build pandoc command with appropriate options
    local pandoc_cmd="pandoc"
    
    # Handle PDF conversion with proper engine
    if [ "$format" = "pdf" ]; then
        # Check for available PDF engines
        if command -v pdflatex &> /dev/null; then
            pandoc_cmd="$pandoc_cmd --pdf-engine=pdflatex"
        elif command -v xelatex &> /dev/null; then
            pandoc_cmd="$pandoc_cmd --pdf-engine=xelatex"
        elif command -v lualatex &> /dev/null; then
            pandoc_cmd="$pandoc_cmd --pdf-engine=lualatex"
        else
            echo "Warning: No LaTeX engine found. Trying default PDF generation..."
            pandoc_cmd="$pandoc_cmd --pdf-engine=wkhtmltopdf"
        fi
    fi
    
    # For formats that need to access image files (docx, pdf, etc.), 
    # we need to provide full paths to the images
    if [ "$format" = "docx" ] || [ "$format" = "pdf" ] || [ "$format" = "html" ]; then
        # Create a temporary file with full image paths
        local temp_md_file="${md_file%.md}_temp.md"
        local md_dir=$(dirname "$md_file")
        
        # Replace image references with full paths (use a simple and robust approach)
        # Use perl for better handling of special characters
        perl -pe "s|!\[image\]\(([^)]+)\)|![image]($md_dir/\$1)|g" "$md_file" > "$temp_md_file"
        
        # Convert using pandoc with the temporary file (suppress image warnings)
        $pandoc_cmd "$temp_md_file" -o "$output_file" --quiet 2>/dev/null
        local result=$?
        
        # Clean up temporary file
        rm -f "$temp_md_file"
        
        if [ $result -eq 0 ]; then
            return 0
        else
            printf "\nError: Failed to convert $md_file to $format\n"
            return 1
        fi
    else
        # For other formats, use the original markdown file (suppress image warnings)
        if $pandoc_cmd "$md_file" -o "$output_file" --quiet 2>/dev/null; then
            return 0
        else
            printf "\nError: Failed to convert $md_file to $format\n"
            return 1
        fi
    fi
}

# Count total files for progress bar
total_files=$(find "$SOURCE_FOLDER" -name "*.cook" -type f | wc -l)
current_file=0

echo "Converting $total_files cooklang files..."

# Process all .cook files in source folder
find "$SOURCE_FOLDER" -name "*.cook" -type f | while read -r cook_file; do
    current_file=$((current_file + 1))
    
    # Show progress bar
    progress=$((current_file * 100 / total_files))
    bar_length=50
    filled_length=$((progress * bar_length / 100))
    bar=$(printf "%*s" $filled_length | tr ' ' '=')
    empty_bar=$(printf "%*s" $((bar_length - filled_length)) | tr ' ' ' ')
    printf "\r[%s%s] %d%% (%d/%d)" "$bar" "$empty_bar" "$progress" "$current_file" "$total_files"
    
    # Get relative path from source folder
    # Remove the source folder path from the beginning of the cook_file path
    rel_path=$(echo "$cook_file" | sed "s|^$SOURCE_FOLDER/||")
    rel_dir=$(dirname "$rel_path")
    
    # Create corresponding directory in destination
    dest_dir="$DEST_FOLDER/$rel_dir"
    mkdir -p "$dest_dir"
    
    # Get recipe title
    recipe_title=$(get_recipe_title "$(basename "$cook_file")")
    
    # Read cooklang content
    if [ ! -r "$cook_file" ]; then
        printf "\nError: Cannot read $cook_file, skipping...\n"
        continue
    fi
    
    content=$(cat "$cook_file")
    
    # Extract components
    servings=$(extract_servings "$content")
    source=$(extract_source "$content")
    ingredients=$(extract_ingredients "$content")
    equipment=$(extract_equipment "$content")
    steps=$(extract_steps "$content")
    
    # Find associated image
    image_name=$(find_image "$cook_file")
    
    # Copy image if it exists
    if [ "$image_name" != "no-image.png" ]; then
        source_image="$(dirname "$cook_file")/$image_name"
        if [ -f "$source_image" ]; then
            cp "$source_image" "$dest_dir/" 2>/dev/null || printf "\nError: Failed to copy image $image_name\n"
        fi
    fi
    
    # Create markdown file
    md_file="$dest_dir/$(basename "$cook_file" .cook).md"
    
    # Handle empty sections
    if [ -z "$ingredients" ]; then
        ingredients="- Aucun ingrédient spécifié"
    fi
    
    if [ -z "$equipment" ]; then
        equipment="- Aucun matériel spécifié"
    fi
    
    if [ -z "$steps" ]; then
        steps="Aucune étape spécifiée"
    fi
    
    # Create ingredients header with servings if available
    if [ -n "$servings" ]; then
        ingredients_header="## Ingrédients (Pour $servings)"
    else
        ingredients_header="## Ingrédients"
    fi
    
    # Create source section if available
    if [ -n "$source" ]; then
        # Extract domain from URL for display - using awk for reliability
        domain=$(echo "$source" | awk -F'://' '{print $2}' | awk -F'/' '{print $1}')
        source_section="Source: [$domain]($source)"
    else
        source_section=""
    fi
    
    # URL encode the image name for proper markdown display
    encoded_image_name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$image_name', safe=''))" 2>/dev/null)
    if [ $? -ne 0 ]; then
        # Fallback: basic URL encoding for common characters
        encoded_image_name=$(echo "$image_name" | sed 's/ /%20/g' | sed 's/à/%C3%A0/g' | sed 's/é/%C3%A9/g' | sed 's/è/%C3%A8/g' | sed 's/ê/%C3%AA/g' | sed 's/ë/%C3%AB/g' | sed 's/ç/%C3%A7/g' | sed 's/ù/%C3%B9/g' | sed 's/û/%C3%BB/g' | sed 's/ü/%C3%BC/g' | sed 's/ô/%C3%B4/g' | sed 's/ö/%C3%B6/g' | sed 's/î/%C3%AE/g' | sed 's/ï/%C3%AF/g' | sed 's/â/%C3%A2/g' | sed 's/ä/%C3%A4/g' | sed 's/ñ/%C3%B1/g' | sed 's/ß/%C3%9F/g')
    fi
    
    # Create the markdown content
    {
        echo "# $recipe_title"
        echo ""
        echo "![image]($encoded_image_name)"
        if [ -n "$source" ]; then
            echo ""
            echo "$source_section"
        fi
        echo ""
        echo "$ingredients_header"
        echo ""
        echo "$ingredients"
        echo ""
        echo "## Matériel"
        echo ""
        echo "$equipment"
        echo ""
        echo "## Étapes"
        echo ""
        echo "$steps"
    } > "$md_file" 2>/dev/null || printf "\nError: Failed to create markdown file $md_file\n"
    
    # Convert to specified format if requested
    if [ -n "$EXPORT_FORMAT" ]; then
        convert_to_format "$md_file" "$EXPORT_FORMAT"
        
        # If conversion was successful, remove the markdown and image files
        if [ $? -eq 0 ]; then
            rm -f "$md_file"
            # Remove the copied image file if it exists
            if [ "$image_name" != "no-image.png" ] && [ -f "$dest_dir/$image_name" ]; then
                rm -f "$dest_dir/$image_name"
            fi
        fi
    fi
done

# Clear the progress bar and show completion
printf "\n\n✅ Conversion completed!\n"
echo "📁 Files saved to: $DEST_FOLDER"
if [ -n "$EXPORT_FORMAT" ]; then
    echo "📄 Format: $EXPORT_FORMAT files created"
    echo "🧹 Cleaned up intermediate files"
fi
