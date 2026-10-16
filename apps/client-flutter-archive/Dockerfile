# Serves a web build made beforehand (Flutter is not in this image):
#   flutter build web --release --no-web-resources-cdn \
#     --dart-define=API_BASE_URL=https://YOUR_DOMAIN/api/v1
#   docker build -t omniassist-web apps/client
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html
