# Dockerfile
FROM rust:1.67 as builder
WORKDIR /usr/src/app
COPY . .
RUN cargo install --path .

FROM debian:buster-slim
COPY --from=builder /usr/local/cargo/bin/axum-app /usr/local/bin/axum-app
CMD ["axum-app"]