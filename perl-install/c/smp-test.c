main() {
  if (detectSMP())
    printf("has smp\n");
  else
    printf("no smp\n");
}
