/* Machine-specific elf macros for i386 et al.  */
#ident "$Id$"

#define ELFCLASSM	ELFCLASS32
#define ELFDATAM	ELFDATA2MSB

#define MATCH_MACHINE(x)  (x == EM_S390)

#define SHT_RELM	SHT_RELA
#define Elf32_RelM	Elf32_Rela
