FROM nginx:alpine

# Copiamos la interfaz interactiva a la carpeta web de Nginx
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80