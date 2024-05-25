#Thanks to Remo
#!/bin/bash
# Update and install Apache2
apt update
apt install -y apache2

# Start and enable Apache2
systemctl start apache2
systemctl enable apache2

# GCP Metadata server base URL and header
METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
METADATA_FLAVOR_HEADER="Metadata-Flavor: Google"

# Use curl to fetch instance metadata
local_ipv4=$(curl -H "${METADATA_FLAVOR_HEADER}" -s "${METADATA_URL}/instance/network-interfaces/0/ip")
zone=$(curl -H "${METADATA_FLAVOR_HEADER}" -s "${METADATA_URL}/instance/zone")
project_id=$(curl -H "${METADATA_FLAVOR_HEADER}" -s "${METADATA_URL}/project/project-id")
network_tags=$(curl -H "${METADATA_FLAVOR_HEADER}" -s "${METADATA_URL}/instance/tags")

# Create a simple HTML page and include instance details
cat <<EOF > /var/www/html/index.html
<html><body>
<h2>I Will Balance My Load On These T*tt*es On Terraform</h2>
<h3><div class="tenor-gif-embed" data-postid="24648981" data-share-method="host" data-aspect-ratio="1.04918" data-width="25%"><a href="https://tenor.com/view/boob-bounce-tits-jiggle-dance-gif-24648981">Boob Bounce Tits GIF</a>from <a href="https://tenor.com/search/boob+bounce-gifs">Boob Bounce GIFs</a></div> <script type="text/javascript" async src="https://tenor.com/embed.js"></script></h3>
<p><b>Instance Name:</b> $(hostname -f)</p>
<p><b>Instance Private IP Address: </b> $local_ipv4</p>
<p><b>Zone: </b> $zone</p>
<p><b>Project ID:</b> $project_id</p>
<p><b>Network Tags:</b> $network_tags</p>
</body></html>
EOF

