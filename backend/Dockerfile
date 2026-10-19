# образ сборки
FROM golang:1.26-alpine AS build

WORKDIR /app

# копирование файлов зависимостей
COPY go.mod go.sum ./
RUN go mod download

# копирование исходного кода
COPY . .

# сборка приложения
RUN CGO_ENABLED=0 go build -ldflags="-w -s" -o /app/server ./cmd/server/main.go


# образ для развертывания
FROM alpine:latest
WORKDIR /app

# копирование исполняемого файла
COPY --from=build /app/server .
COPY --from=build /app/SQL_scripts ./SQL_scripts

EXPOSE 8080
CMD ["./server"] 
