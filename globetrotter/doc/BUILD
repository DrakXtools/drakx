        How to build Mandrakelinux Globetrotter:
        ========================================

- you need first to install all the drakxtools' build dependancies
  (thus running "urpmi /SRPMS/drakxtools-*" may be quite helpful)

- copy the mdk10.0 DVD in /export
- leave main as Mandrake/RPMS
- copy h[cs]f*, FlashPlayer*, RealPlayer* into Mandrake/RPMS from Mandrake/RPMS[23]
- move contribs as Mandrake/RPMS2
- move other RPMS? somewhere else
- add packages from ~tv/rpm/lacie on cluster
- add updates from /mnt/BIG/dis/updates/10.0
- add updated proprietary packages for kernel update from kameha
  (nplanel's work machine):
  echo "mget *2.4.25.5mdk* *2.6.3.13mdk*" | \
lftp -u a,a ftp://kameha:/~/../nplanel/rpm/prop/RPMS/i586/
- run the following in order to remove duplicated packages:
  doble [A-Z] | xargs rm -f
  doble [a-g] | xargs rm -f
  doble [h-z] | xargs rm -f
- run "gendistrib --noclean /export"
- plug the LaCie disk
- check out the whole gi cvs module
- run "C_DRAKX=1 make c" in gi/perl-install
- go into gi/globetrotter
- run make_live --partition --format --install --post in order to
  prepare the disk
