#!/bin/bash
# Smart Module Load
# Usage: sml.sh <module_name>

if [ "$#" -ne 1 ]; then
    echo "Smart Module Load"
    echo "Usage: $(basename $0) <module_name>"
    exit 1
fi

module_name="$1"

# Function to check if a module is loaded
is_module_loaded() {
    module list 2>&1 | grep -q "$module_name"
}

# Check if the module is already loaded
if is_module_loaded "$module_name"; then
    echo "Module '$module_name' is already loaded."
else
    echo "Loading module '$module_name'..."
    module load "$module_name"
    
    # Verify if the module was loaded successfully
    if is_module_loaded "$module_name"; then
        echo "Module '$module_name' loaded successfully."
    else
        echo "Failed to load module '$module_name'."
        exit 1
    fi
fi
