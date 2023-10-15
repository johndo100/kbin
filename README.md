# Yet Another Kbin Docker Image

I've tried official Kbin official image but it was not straighforward.

The Dockerfile was for Docker and it make more complicate when I was working with podman/buildah.

So I make another image based on baremetal approach.

This image bundle with nginx, php, nodejs, yarn and kbin source code.

You'll need to deploy it manual way and it require more understading.

Some services need to deploy in separate container:
- PostgreSQL
- Redis (optional)
- Mercure (optional)
- RabbitMQ (optional)

Change your .env file in `/var/www/kbin` before you run:
- `composer install --no-dev`
- `composer dump-env prod`
- `php bin/console doctrine:database:create`
- `php bin/console doctrine:migrations:migrate`

Default user to run nginx and php-fpm: `http`.

Default listen port: `80`.

You can read more information [here](https://codeberg.org/Kbin/kbin-core/wiki/Admin-Bare-Metal-Guide).

I was trying to make it based on Alpine Linux but php iconv extension need iconv but I'm not sure if it works well with musl instead of glibc.

This image is based on `debian-slim`.

You can pull it here `johndo100/kbin`.

Change it the way you like in Dockerfile.
