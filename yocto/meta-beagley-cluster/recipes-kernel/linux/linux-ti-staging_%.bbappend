# Appliance builds do not ship TI source IPK side packages, and generating the
# kernel source archive triggers a very large git repack that is not needed for
# the flashable runtime image.
CREATE_SRCIPK:pn-linux-ti-staging = "0"
