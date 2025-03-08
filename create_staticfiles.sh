#!/bin/bash
# This script creates basic static files for the Radius Manager project

# Define the base static directory (adjust if needed)
PROJECT_STATIC_DIR="radius-manager/app/static"

# Create the CSS directory and file
mkdir -p "${PROJECT_STATIC_DIR}/css"
cat > "${PROJECT_STATIC_DIR}/css/style.css" << 'EOF'
/* style.css - Basic styles for Radius Manager */
body {
    font-family: Arial, sans-serif;
    background: #f4f4f4;
    margin: 0;
    padding: 0;
}

header {
    background: #333;
    color: #fff;
    padding: 10px 0;
}

header nav ul {
    list-style: none;
    display: flex;
    justify-content: center;
    padding: 0;
}

header nav ul li {
    margin: 0 15px;
}

header nav ul li a {
    color: #fff;
    text-decoration: none;
}

.container {
    width: 90%;
    margin: 20px auto;
    padding: 20px;
    background: #fff;
    box-shadow: 0 0 10px rgba(0,0,0,0.1);
}

footer {
    text-align: center;
    padding: 10px;
    background: #333;
    color: #fff;
    position: fixed;
    width: 100%;
    bottom: 0;
}
EOF

# Create the JS directory and file
mkdir -p "${PROJECT_STATIC_DIR}/js"
cat > "${PROJECT_STATIC_DIR}/js/script.js" << 'EOF'
// script.js - Basic JavaScript for Radius Manager
document.addEventListener("DOMContentLoaded", function(){
    console.log("Radius Manager loaded");
    // Add your custom JS functionality here
});
EOF

echo "Static files created successfully in ${PROJECT_STATIC_DIR}"
