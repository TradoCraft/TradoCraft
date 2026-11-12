# API image: Rust binaries (staff API, worker, customer portal server) + Typst for PDF rendering
# + templates.

FROM rust:1-trixie AS typst
ARG TYPST_VERSION=0.15.1
RUN cargo install typst-cli --locked --version ${TYPST_VERSION}

FROM rust:1-trixie AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY apps apps
COPY crates crates
COPY migrations migrations
COPY seed seed
RUN cargo build --release -p tradocraft-api -p tradocraft-worker -p tradocraft-portal-api

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --home /app tradocraft
WORKDIR /app
COPY --from=typst /usr/local/cargo/bin/typst /usr/local/bin/typst
COPY --from=build /src/target/release/tradocraft-api /usr/local/bin/tradocraft-api
COPY --from=build /src/target/release/tradocraft-worker /usr/local/bin/tradocraft-worker
# The customer-facing server (ADR 0050): run it with `command: ["tradocraft-portal-api"]`.
COPY --from=build /src/target/release/tradocraft-portal-api /usr/local/bin/tradocraft-portal-api
COPY templates templates
USER tradocraft
ENV BIND_ADDR=0.0.0.0:8080 TEMPLATE_DIR=/app/templates TYPST_BIN=/usr/local/bin/typst
EXPOSE 8080
CMD ["tradocraft-api"]
