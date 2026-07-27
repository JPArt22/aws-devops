FROM nginx:alpine

# Eliminamos la página por defecto de Nginx
RUN rm -rf /usr/share/nginx/html/*

# Copiamos nuestra app de gestión de usuarios
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80