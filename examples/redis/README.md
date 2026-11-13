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
docker exec glimit-redis redis-cli HGETALL 'glimit:"127.0.0.1":1000'
```

## Cleanup

```sh
docker stop glimit-redis && docker rm glimit-redis
```

## How It Works

`redis_store.new` in `src/redis_store.gleam` creates a `glimit.Store` adapter. Each bucket is a Redis hash guarded by a lock key (`<key>:lock`) holding a random token. Every operation is a single Lua script, so it is atomic and takes one round trip:

- **lock_and_get**: Sets the lock with `SET <key>:lock <token> NX PX 5000` and reads the bucket with `HGETALL`. If the lock is held, it waits for up to 500 ms.
- **set_and_unlock**: Writes the bucket with `HSET`, sets a TTL with `EXPIRE` and deletes the lock, but only if the lock still holds our token. If the lock expired and was taken over by another request, nothing is written and the hit returns `Unavailable`.
- **unlock**: Deletes the lock, but only if it still holds our token.

Every reply has to include the token, so a reply meant for another command is never taken as our own. When a command times out, the store assumes it may have run and releases its lock, which is safe because only our own token is deleted.

The lock expires after 5 seconds, in case its holder crashes. A hit must finish within that time, including the rate and burst limit functions.

Requests run concurrently, so `src/app.gleam` uses a connection pool. A single connection cannot be shared between processes.

The rate limiter fails open — if Redis is unavailable or the lock can't be acquired in time, requests are allowed through.

The bucket and its lock key are used in the same script, so Redis Cluster is not supported.

## Running the Tests

The tests need Redis on `localhost:6379`:

```sh
gleam test
```
