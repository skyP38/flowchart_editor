FROM ubuntu AS build

RUN apt-get update
RUN apt-get install -y curl git unzip

RUN git clone https://github.com/flutter/flutter.git 

ENV PATH="/flutter/bin:${PATH}"

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

RUN flutter clean
ARG API_BASE_URL=http://localhost:8080
RUN flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL --no-wasm-dry-run


FROM nginx:alpine

COPY --from=build /app/build/web  /usr/share/nginx/html

COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
