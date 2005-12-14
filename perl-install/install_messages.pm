package install_messages; # $Id$

use diagnostics;
use strict;

use common;

sub main_license() {
#-PO: keep the double empty lines between sections, this is formatted a la LaTeX
N("Introduction

The operating system and the different components available in the Mandriva Linux distribution 
shall be called the \"Software Products\" hereafter. The Software Products include, but are not 
restricted to, the set of programs, methods, rules and documentation related to the operating 
system and the different components of the Mandriva Linux distribution.


1. License Agreement

Please read this document carefully. This document is a license agreement between you and  
Mandriva S.A. which applies to the Software Products.
By installing, duplicating or using the Software Products in any manner, you explicitly 
accept and fully agree to conform to the terms and conditions of this License. 
If you disagree with any portion of the License, you are not allowed to install, duplicate or use 
the Software Products. 
Any attempt to install, duplicate or use the Software Products in a manner which does not comply 
with the terms and conditions of this License is void and will terminate your rights under this 
License. Upon termination of the License,  you must immediately destroy all copies of the 
Software Products.


2. Limited Warranty

The Software Products and attached documentation are provided \"as is\", with no warranty, to the 
extent permitted by law.
Mandriva S.A. will, in no circumstances and to the extent permitted by law, be liable for any special,
incidental, direct or indirect damages whatsoever (including without limitation damages for loss of 
business, interruption of business, financial loss, legal fees and penalties resulting from a court 
judgment, or any other consequential loss) arising out of  the use or inability to use the Software 
Products, even if Mandriva S.A. has been advised of the possibility or occurrence of such 
damages.

LIMITED LIABILITY LINKED TO POSSESSING OR USING PROHIBITED SOFTWARE IN SOME COUNTRIES

To the extent permitted by law, Mandriva S.A. or its distributors will, in no circumstances, be 
liable for any special, incidental, direct or indirect damages whatsoever (including without 
limitation damages for loss of business, interruption of business, financial loss, legal fees 
and penalties resulting from a court judgment, or any other consequential loss) arising out 
of the possession and use of software components or arising out of  downloading software components 
from one of Mandriva Linux sites  which are prohibited or restricted in some countries by local laws.
This limited liability applies to, but is not restricted to, the strong cryptography components 
included in the Software Products.


3. The GPL License and Related Licenses

The Software Products consist of components created by different persons or entities.  Most 
of these components are governed under the terms and conditions of the GNU General Public 
Licence, hereafter called \"GPL\", or of similar licenses. Most of these licenses allow you to use, 
duplicate, adapt or redistribute the components which they cover. Please read carefully the terms 
and conditions of the license agreement for each component before using any component. Any question 
on a component license should be addressed to the component author and not to Mandriva.
The programs developed by Mandriva S.A. are governed by the GPL License. Documentation written 
by Mandriva S.A. is governed by a specific license. Please refer to the documentation for 
further details.


4. Intellectual Property Rights

All rights to the components of the Software Products belong to their respective authors and are 
protected by intellectual property and copyright laws applicable to software programs.
Mandriva S.A. reserves its rights to modify or adapt the Software Products, as a whole or in 
parts, by all means and for all purposes.
\"Mandriva\", \"Mandriva Linux\" and associated logos are trademarks of Mandriva S.A.  


5. Governing Laws 

If any portion of this agreement is held void, illegal or inapplicable by a court judgment, this 
portion is excluded from this contract. You remain bound by the other applicable sections of the 
agreement.
The terms and conditions of this License are governed by the Laws of France.
All disputes on the terms of this license will preferably be settled out of court. As a last 
resort, the dispute will be referred to the appropriate Courts of Law of Paris - France.
For any question on this document, please contact Mandriva S.A.  
");
}

sub warning_about_patents() {
N("Warning: Free Software may not necessarily be patent free, and some Free
Software included may be covered by patents in your country. For example, the
MP3 decoders included may require a licence for further usage (see
http://www.mp3licensing.com for more details). If you are unsure if a patent
may be applicable to you, check your local laws.");
}
sub com_license() { 
#-PO: keep the double empty lines between sections, this is formatted a la LaTeX
N("
Warning

Please read carefully the terms below. If you disagree with any
portion, you are not allowed to install the next CD media. Press 'Refuse' 
to continue the installation without using these media.


Some components contained in the next CD media are not governed
by the GPL License or similar agreements. Each such component is then
governed by the terms and conditions of its own specific license. 
Please read carefully and comply with such specific licenses before 
you use or redistribute the said components. 
Such licenses will in general prevent the transfer,  duplication 
(except for backup purposes), redistribution, reverse engineering, 
de-assembly, de-compilation or modification of the component. 
Any breach of agreement will immediately terminate your rights under 
the specific license. Unless the specific license terms grant you such
rights, you usually cannot install the programs on more than one
system, or adapt it to be used on a network. In doubt, please contact 
directly the distributor or editor of the component. 
Transfer to third parties or copying of such components including the 
documentation is usually forbidden.


All rights to the components of the next CD media belong to their 
respective authors and are protected by intellectual property and 
copyright laws applicable to software programs.
");
}

sub install_completed() {
#-PO: keep the double empty lines between sections, this is formatted a la LaTeX
N("Congratulations, installation is complete.
Remove the boot media and press Enter to reboot.


For information on fixes which are available for this release of Mandriva Linux,
consult the Errata available from:


%s


Information on configuring your system is available in the post
install chapter of the Official Mandriva Linux User's Guide.",
"http://www.mandriva.com/security");
}

1;
