# Build stage
FROM golang:1.22-alpine AS builder
WORKDIR /build
COPY go.mod ./
COPY cmd/ ./cmd/
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s -X main.buildTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" -o /payments-api ./cmd/payments-api

# Runtime stage
FROM gcr.io/distroless/static:nonroot
WORKDIR /
COPY --from=builder /payments-api /payments-api

USER 65532:65532
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/payments-api"] || exit 1

ENTRYPOINT ["/payments-api"]
