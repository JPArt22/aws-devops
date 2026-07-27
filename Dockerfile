FROM nginx:alpine

RUN echo '<!DOCTYPE html><html><head><title>DevOps Demo</title><style>body{font-family:sans-serif;background:#0f172a;color:#f8fafc;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;}h1{color:#38bdf8;}</style></head><body><div><h1>🚀 ¡Desplegado exitosamente mediante CI/CD con GitHub Actions + ECS Fargate!</h1></div></body></html>' > /usr/share/nginx/html/index.html

EXPOSE 80