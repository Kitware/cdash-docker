# cdash-docker
Deploy a cdash instance with docker and zero guess work!

## How?

Build with docker:

```bash
docker build -t "kitware/cdash-docker" .
```

...or build with docker-compose

```bash
docker-compose build
```

## Deploy example application using docker-compose

See `docker-compose.yml` for an example of how to deploy using the
`cdash-docker` image.  Add your own customizations, or deploy the example as-is!

```bash
docker-compose up -d
```

Check on your instance's status:

```bash
docker-compose ps
```

Once docker reports that cdash is "healthy", you're good to go!  Browse your
cdash instance at `localhost:8080`.
