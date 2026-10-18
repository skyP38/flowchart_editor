FROM ubuntu:24.04 AS build

WORKDIR /app

COPY pubspeck.yaml pubspeck.lock ./
RUN flutter pub get

COPY . .

ARG API_BASE_URL=http://localhost:8080
RUN flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL


FROM nginx:alpine

COPY --from=build /app/build/web  /usr/share/nginx/html

COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
