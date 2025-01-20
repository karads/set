cat << 'EOF' > ~/move.sh
#!/bin/bash

# Directories to move files to
destinations=(
  "/mnt/up1/"
  "/mnt/up2/"
  "/mnt/up3/"
  "/mnt/up4/"
  "/mnt/up5/"
  "/mnt/up6/"
  "/mnt/up7/"
  "/mnt/up8/"
  "/mnt/up9/"
  "/mnt/up10/"
)

index=0

echo "Starting..."

while true; do
  file=$(inotifywait -q -e create,moved_to --format '%w%f' /mnt/pw/)
  if [[ $file == *.fpt ]]; then
    mv "$file" "${destinations[$index]}"
    echo "Moved $file to ${destinations[$index]}"
    # Increment index or reset to 0 if we've hit the end of the destinations array
    ((index=(index+1)%${#destinations[@]}))
  fi
done
EOF
