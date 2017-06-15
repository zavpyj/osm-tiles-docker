#!/bin/sh

##
# Run OpenStreetMap tile server operations
#

# Command prefix that runs the command as the web user
asweb="setuser www-data"

die () {
    msg=$1
    echo "FATAL ERROR: " msg > 2
    exit
}

_startservice () {
    sv start $1 || die "Could not start $1"
}

startdb () {
    _startservice postgresql
}

initdb () {
    echo "Initialising postgresql"
    if [ -d /var/lib/postgresql/9.5/main ] && [ $( ls -A /var/lib/postgresql/9.5/main | wc -c ) -ge 0 ]
    then
        die "Initialisation failed: the directory is not empty: /var/lib/postgresql/9.5/main"
    fi

    mkdir -p /var/lib/postgresql/9.5/main && chown -R postgres /var/lib/postgresql/
    sudo -u postgres -i /usr/lib/postgresql/9.5/bin/initdb --pgdata /var/lib/postgresql/9.5/main
    ln -s /etc/ssl/certs/ssl-cert-snakeoil.pem /var/lib/postgresql/9.5/main/server.crt
    ln -s /etc/ssl/private/ssl-cert-snakeoil.key /var/lib/postgresql/9.5/main/server.key

    startdb
    createuser
    createdb
}

createuser () {
    USER=www-data
    echo "Creating user $USER"
    setuser postgres createuser -s $USER
}

createdb () {
    dbname=gis
    echo "Creating database $dbname"
    cd /var/www

    # Create the database
    setuser postgres createdb -O www-data $dbname

    # Install the Postgis schema
    $asweb psql -d $dbname -f /usr/share/postgresql/9.5/contrib/postgis-2.2/postgis.sql

    $asweb psql -d $dbname -c 'CREATE EXTENSION HSTORE;'

    # Set the correct table ownership
    $asweb psql -d $dbname -c 'ALTER TABLE geometry_columns OWNER TO "www-data"; ALTER TABLE spatial_ref_sys OWNER TO "www-data";'

    # Add Spatial Reference Systems from PostGIS
    $asweb psql -d $dbname -f /usr/share/postgresql/9.5/contrib/postgis-2.2/spatial_ref_sys.sql
}

import () {
    startdb
    # Assign from env var or find the most recent import.pbf or import.osm
    import=${OSM_IMPORT_FILE:-$( ls -1t /data/import.pbf /data/import.osm 2>/dev/null | head -1 )}
    test -n "${import}" || \
        die "No import file present: expected specification via OSM_IMPORT_FILE or existence of /data/import.osm or /data/import.pbf"

    echo "Removing indexes from gis..."
    $asweb psql -d gis -f /usr/share/mapnik/openstreetmap-carto/drop_indexes.sql

    echo "Importing ${import} into gis"
    echo "$OSM_IMPORT_CACHE" | grep -P '^[0-9]+$' || \
        die "Unexpected cache type: expected an integer but found: ${OSM_IMPORT_CACHE}"

    number_processes=`nproc`

    # Limit to 8 to prevent overwhelming pg with connections
    if test $number_processes -ge 8
    then
        number_processes=8
    fi

    append=$1
    if [ "$append" = "append" ]
    then
        append="--append "
    else
        append=""
    fi

    $asweb osm2pgsql $append--slim --hstore --cache $OSM_IMPORT_CACHE --database gis --number-processes $number_processes --style /usr/share/mapnik/openstreetmap-carto/openstreetmap-carto.style $import

    echo "Creating indexes into gis..."
    $asweb psql -d gis -f /usr/share/mapnik/openstreetmap-carto/indexes.sql

    echo "Import done!"
}

importappend () {
    import "append"
}

# render tiles via render_list
render () {
    startdb
    _startservice renderd
    # wait for services to start
    sleep 10
    min_zoom=${OSM_RENDER_MIN_ZOOM:-0}
    max_zoom=${OSM_RENDER_MAX_ZOOM:-8}
    render_force_arg=$( [ "$OSM_RENDER_FORCE" != false ] && echo '-f' || echo '' )
    number_processes=${OSM_RENDER_THREADS:-`nproc`}
    # Limit to 8 to prevent overwhelming pg with connections
    if test $number_processes -ge 8
    then
        number_processes=8
    fi

    echo "Rendering OSM tiles"
    if [ -n "$OSM_RENDER_X_MIN" ] && [ -n "$OSM_RENDER_X_MAX" ] && [ -n "$OSM_RENDER_Y_MIN" ] && [ -n "$OSM_RENDER_Y_MAX" ]
    then
        echo "$asweb /opt/render_list_geo.pl -n $number_processes $render_force_arg -z $min_zoom -Z $max_zoom -x $OSM_RENDER_X_MIN -X $OSM_RENDER_X_MAX -y $OSM_RENDER_Y_MIN -Y $OSM_RENDER_Y_MAX"
        $asweb /opt/render_list_geo.pl -n $number_processes $render_force_arg -z $min_zoom -Z $max_zoom -x $OSM_RENDER_X_MIN -X $OSM_RENDER_X_MAX -y $OSM_RENDER_Y_MIN -Y $OSM_RENDER_Y_MAX
    else
        echo "$asweb render_list $render_force_arg --all --min-zoom $min_zoom --max-zoom $max_zoom --num-threads $number_processes"
        $asweb render_list $render_force_arg --all --min-zoom $min_zoom --max-zoom $max_zoom --num-threads $number_processes
    fi
}

dropdb () {
    echo "Dropping database"
    cd /var/www
    setuser postgres dropdb gis
}

cli () {
    echo "Running bash"
    cd /var/www
    exec bash
}

startservices () {
    startdb
    _startservice renderd
    startweb
}

startweb () {
    if [ -n "$OSM_WEB_AUTHORIZED_IDS" ] || [ -n "$OSM_WEB_AUTHORIZED_REFERERS" ]
    then
        if [ -n "$OSM_WEB_AUTHORIZED_IDS" ]
        then
            sed -i -e "s/#Authorized key ids: //" /etc/apache2/mods-available/rewrite.conf
            sed -i -e "s/{{KEY_ID}}/$OSM_WEB_AUTHORIZED_IDS/" /etc/apache2/mods-available/rewrite.conf
        fi
        if [ -n "$OSM_WEB_AUTHORIZED_REFERERS" ]
        then
            sed -i -e "s/#Authorized referers: //" /etc/apache2/mods-available/rewrite.conf
            sed -i -e "s/{{AUTHORIZED_REFERERS}}/$OSM_WEB_AUTHORIZED_REFERERS/" /etc/apache2/mods-available/rewrite.conf
        fi
        sed -i -e "s/#Include mods-available\/rewrite.conf/Include mods-available\/rewrite.conf/" /etc/apache2/sites-available/000-default.conf
        a2enmod rewrite
    fi
    _startservice apache2
}

help () {
    cat /usr/local/share/doc/run/help.txt
    exit
}

start () {
    if [ -f /tmp/InitDone.txt ]; then
        echo "[`date '+%H:%M:%S'`] Initialization already done"
    else
        echo ""
        echo "-----------------------------------------------------------------"
        echo "[`date '+%H:%M:%S'`] initdb"
        initdb
        echo ""
        echo "-----------------------------------------------------------------"
        echo "[`date '+%H:%M:%S'`] import"
        import
        echo ""
        echo "-----------------------------------------------------------------"
        echo "[`date '+%H:%M:%S'`] render"
        render
    fi
    touch /tmp/InitDone.txt

    echo ""
    echo "====================================================================="
    echo "[`date '+%H:%M:%S'`] startservices"
    echo ""
    echo "---------------------------------------------------------------------"
    echo "[`date '+%H:%M:%S'`] startdb"
    startdb
    echo ""
    echo "---------------------------------------------------------------------"
    echo "[`date '+%H:%M:%S'`] _startservice renderd"
    _startservice renderd
    echo ""
    echo "---------------------------------------------------------------------"
    echo "[`date '+%H:%M:%S'`] startweb"
    startweb
}

# wait until 2 seconds after boot when runit will have started supervising the services.

sleep 2

# Execute the specified command sequence
for arg
do
    $arg;
done

# Unless there is a terminal attached don't exit, otherwise docker
# will also exit
if ! tty --silent
then
    # Wait forever (see
    # http://unix.stackexchange.com/questions/42901/how-to-do-nothing-forever-in-an-elegant-way).
    tail -f /dev/null
fi
