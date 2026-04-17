FROM nginx:1.26-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY html /usr/share/nginx/html/management
EXPOSE 80
# nginx-alpine 이미지에 이미 CMD ["nginx", "-g", "daemon off;"] 명령이 포함되어 있어서, 별도의 CMD 명령을 작성할 필요가 없음!