/* Machine-specific elf macros for ARM.  */
#ident "$Id$"

#define ELFCLASSM	ELFCLASS32
#define ELFDATAM	ELFDATA2LSB

#define MATCH_MACHINE(x)  (x == EM_ARM)

#define SHT_RELM	SHT_REL
#define Elf32_RelM	Elf32_Rel
