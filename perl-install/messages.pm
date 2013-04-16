package messages; # $Id$

use diagnostics;
use strict;

use common;

sub main_license() {
    my ($us, $google) = @_;
#-PO: keep the double empty lines between sections, this is formatted a la LaTeX
N("Introduction

The operating system and the different components available in the Moondrake GNU/Linux distribution 
shall be called the \"Software Products\" hereafter. The Software Products include, but are not 
restricted to, the set of programs, methods, rules and documentation related to the operating 
system and the different components of the Moondrake GNU/Linux distribution, and any applications 
distributed with these products provided by Moondrake's licensors or suppliers.


1. License Agreement

Please read this document carefully. This document is a license agreement between you and  
Moondrake which applies to the Software Products.
By installing, duplicating or using any of the Software Products in any manner, you explicitly 
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
Neither Moondrake nor its licensors or suppliers will, in any circumstances and to the extent 
permitted by law, be liable for any special, incidental, direct or indirect damages whatsoever 
(including without limitation damages for loss of business, interruption of business, financial 
loss, legal fees and penalties resulting from a court judgment, or any other consequential loss) 
arising out of  the use or inability to use the Software Products, even if Moondrake or its 
licensors or suppliers have been advised of the possibility or occurrence of such damages.

LIMITED LIABILITY LINKED TO POSSESSING OR USING PROHIBITED SOFTWARE IN SOME COUNTRIES

To the extent permitted by law, neither Moondrake nor its licensors, suppliers or
distributors will, in any circumstances, be liable for any special, incidental, direct or indirect 
damages whatsoever (including without limitation damages for loss of business, interruption of 
business, financial loss, legal fees and penalties resulting from a court judgment, or any 
other consequential loss) arising out of the possession and use of software components or 
arising out of  downloading software components from one of Moondrake GNU/Linux sites which are 
prohibited or restricted in some countries by local laws.
This limited liability applies to, but is not restricted to, the strong cryptography components 
included in the Software Products.
However, because some jurisdictions do not allow the exclusion or limitation or liability for 
consequential or incidental damages, the above limitation may not apply to you.  
%s

3. The GPL License and Related Licenses

The Software Products consist of components created by different persons or entities. %s
Most of these licenses allow you to use, duplicate, adapt or redistribute the components which 
they cover. Please read carefully the terms and conditions of the license agreement for each component 
before using any component. Any question on a component license should be addressed to the component 
licensor or supplier and not to Moondrake.
The programs developed by Moondrake are governed by the GPL License. Documentation written 
by Moondrake is governed by a specific license. Please refer to the documentation for 
further details.


4. Intellectual Property Rights

All rights to the components of the Software Products belong to their respective authors and are 
protected by intellectual property and copyright laws applicable to software programs.
Moondrake and its suppliers and licensors reserves their rights to modify or adapt the Software 
Products, as a whole or in parts, by all means and for all purposes.
\"Moondrake\", \"Moondrake GNU/Linux\" and associated logos are trademarks of Moondrake  


5. Governing Laws 

If any portion of this agreement is held void, illegal or inapplicable by a court judgment, this 
portion is excluded from this contract. You remain bound by the other applicable sections of the 
agreement.
The terms and conditions of this License are governed by the Laws of France.
All disputes on the terms of this license will preferably be settled out of court. As a last 
resort, the dispute will be referred to the appropriate Courts of Law of Paris - France.
For any question on this document, please contact Moondrake",
$us ? "\n\n" . N("You agree not to (i) sell, export, re-export, transfer, divert, disclose technical data, or 
dispose of, any Software to any person, entity, or destination prohibited by US export laws 
or regulations including, without limitation, Cuba, Iran, North Korea, Sudan and Syria; or 
(ii) use any Software for any use prohibited by the laws or regulations of the United States.

U.S. GOVERNMENT RESTRICTED RIGHTS. 

The Software Products and any accompanying documentation are and shall be deemed to be 
\"commercial computer software\" and \"commercial computer software documentation,\" respectively, 
as defined in DFAR 252.227-7013 and as described in FAR 12.212. Any use, modification, reproduction, 
release, performance, display or disclosure of the Software and any accompanying documentation 
by the United States Government shall be governed solely by the terms of this Agreement and any 
other applicable licence agreements and shall be prohibited except to the extent expressly permitted 
by the terms of this Agreement.") . "\n" : '',
$google ? N("Most of these components, but excluding the applications and software provided by Google Inc. or 
its subsidiaries (\"Google Software\"), are governed under the terms and conditions of the GNU 
General Public Licence, hereafter called \"GPL\", or of similar licenses.")
 : N("Most of these components are governed under the terms and conditions of the GNU 
General Public Licence, hereafter called \"GPL\", or of similar licenses."));
}

sub warning_about_patents() {
N("Warning: Free Software may not necessarily be patent free, and some Free
Software included may be covered by patents in your country. For example, the
MP3 decoders included may require a licence for further usage (see
http://www.mp3licensing.com for more details). If you are unsure if a patent
may be applicable to you, check your local laws.");
}

sub google_provisions() {
N("6. Additional provisions applicable to those Software Products provided by Google Inc. (\"Google Software\")

(a)  You acknowledge that Google or third parties own all rights, title and interest in and to the Google 
Software, portions thereof, or software provided through or in conjunction with the Google Software, including
without limitation all Intellectual Property Rights. \"Intellectual Property Rights\" means any and all rights 
existing from time to time under patent law, copyright law, trade secret law, trademark law, unfair competition 
law, database rights and any and all other proprietary rights, and any and all applications, renewals, extensions 
and restorations thereof, now or hereafter in force and effect worldwide. You agree not to modify, adapt, 
translate, prepare derivative works from, decompile, reverse engineer, disassemble or otherwise attempt to derive 
source code from Google Software. You also agree to not remove, obscure, or alter Google's or any third party's 
copyright notice, trademarks, or other proprietary rights notices affixed to or contained within or accessed in 
conjunction with or through the Google Software.  

(b)  The Google Software is made available to you for your personal, non-commercial use only.
You may not use the Google Software in any manner that could damage, disable, overburden, or impair Google's 
search services (e.g., you may not use the Google Software in an automated manner), nor may you use Google 
Software in any manner that could interfere with any other party's use and enjoyment of Google's search services
or the services and products of the third party licensors of the Google Software.

(c)  Some of the Google Software is designed to be used in conjunction with Google's search and other services.
Accordingly, your use of such Google Software is also defined by Google's Terms of Service located at 
http://www.google.com/terms_of_service.html and Google's Toolbar Privacy Policy located at 
http://www.google.com/support/toolbar/bin/static.py?page=privacy.html.

(d)  Google Inc. and each of its subsidiaries and affiliates are third party beneficiaries of this contract 
and may enforce its terms.");
}

sub install_completed() {
#-PO: keep the double empty lines between sections, this is formatted a la LaTeX
N("Congratulations, installation is complete.
Remove the boot media and press Enter to reboot.


For information on fixes which are available for this release of Moondrake GNU/Linux,
consult the Errata available from:


%s


Information on configuring your system is available in the post
install chapter of the Official Moondrake GNU/Linux User's Guide.",
'http://www.mandriva.com/en/security/advisories');
}

1;
