# zavpyj/osm-tiles

<!--About-->

This is a **Docker** image that provides a full stack for working w/ **OpenStreetMap** data. It can be used to:

- Initialize **PostgreSQL** database w/ **PostGIS** extensions: `initdb`
- Import **OpenStreetMap** data into **PostgreSQL** database: `import`
- Optionally pre-generate tiles: `render`
- Serve pre-generated (if available) and dynamically generated tiles from **Apache**, **renderd** and **mapnik** via a **Leaflet** interface: `startservices`
- Serve exclusively pre-generated tiles from **Apache** via a **Leaflet** interface: `startweb`

## Background

This image is adapted from [`ncareol/osm-tiles-docker`](https://github.com/ncareol/osm-tiles-docker), which is based on [`homme/openstreetmap-tiles-docker`](https://hub.docker.com/r/homme/openstreetmap-tiles-docker/), which is based on the [Switch2OSM instructions](https://switch2osm.org/serving-tiles/manually-building-a-tile-server-14-04/).

It runs **Ubuntu** 16.04 (Xenial) and is based on [phusion/baseimage-docker](https://github.com/phusion/baseimage-docker). It includes:

- **PostgreSQL** `9.5`
- **PostGIS** extensions
- **Apache** `2.4`
- [**osm2pgsql**](http://wiki.openstreetmap.org/wiki/Osm2pgsql)
- [**mapnik**](http://mapnik.org/)
- [**openstreetmap-carto**](https://github.com/gravitystorm/openstreetmap-carto), a CartoCSS template (mapnik style) for OpenStreetMap data
- [**mod_tile**](http://wiki.openstreetmap.org/wiki/Mod_tile), an **Apache** module that also provides scripts for rendering tiles

## Usage

To build this image:

```sh
$ docker build -t zavpyj/osm-tiles .
```

Command reference is available in `help.txt` or by running the image:

```sh
$ docker run --rm zavpyj/osm-tiles
```

### Atomic Usage

To persist the postgresql database and the generated tiles, it is advised to create beforehand a docker's named volume (mandatory to persist on Windows OS):

```sh
$ docker volume create --name nvpostgisdata -d local
$ docker volume create --name nvtiles -d local
```

Using [`Docker Compose`](https://docs.docker.com/compose/) and a dedicated [`docker-compose.yml`](https://docs.docker.com/compose/compose-file/) configuration file, zavpyj/osm-tiles is even simpler to use:
```sh
$ docker-compose run --rm app-osm initdb
$ docker-compose run --rm app-osm import
$ docker-compose run --rm app-osm render
$ docker-compose up -d
```

### Direct Usage

Initialise if not already done (initdb+import+render) and Start OSM server (startservices)

```sh
$ docker-compose -f osm.yml up -d
```
