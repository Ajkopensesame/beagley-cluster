# The appliance image does not need gold, and keeping it enabled has proven
# unstable in the Docker-based TI builder. Stick to the default BFD linker.
LDGOLD = "--disable-gold --enable-ld=default"
LDGOLD_ALTS = ""
