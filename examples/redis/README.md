# Redis Store Example

This example demonstrates distributed rate limiting with glimit using Redis as the storage backend via [valkyrie](https://hexdocs.pm/valkyrie/).

Rate limit state is stored in Redis hashes, so multiple application instances can share the same rate limits.

## Prerequisites

- [Gleam](https://gleam.run/getting-started/installing/) installed
- Docker installed (for running Redis)

## Running Redis with Docker

Start a Redis container:

```sh
docker run -d --name glimit-redis -p 6379:6379 redis:7-alpine
```

Verify it's running:

```sh
docker exec glimit-redis redis-cli ping
# Should print: PONG
```

## Running the Example

```sh
gleam run
```

The server starts on `http://localhost:8000`. It allows 1 request per second with a burst of 5.

## Testing the Rate Limit

Send requests in quick succession:

```sh
for i in $(seq 1 8); do
  echo "Request $i: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000)"
done
```

The first 5 requests return `200`, the rest return `429`.

## Inspecting Redis State

You can see the stored bucket state:

```sh
docker exec glimit-redis redis-cli KEYS 'glimit:*'
docker exec glimit-redis redis-cli HGETALL 'glimit:#(127, 0, 0, 1)'
```

## Cleanup

```sh
docker stop glimit-redis && docker rm glimit-redis
```

## How It Works

The `redis_store` function in `src/app.gleam` creates a `glimit.Store` adapter that:

- **get**: Reads bucket state from a Redis hash using `HGETALL`, then parses it with `bucket.from_pairs`
- **set**: Writes bucket state to a Redis hash using `HSET`, then sets a TTL with `EXPIRE`
- **lock**: Acquires a distributed lock using `SET key:lock 1 NX EX 5` (auto-expires after 5 seconds)
- **unlock**: Releases the lock with `DEL key:lock`

The rate limiter fails open — if Redis is unavailable or the lock can't be acquired, requests are allowed through.
