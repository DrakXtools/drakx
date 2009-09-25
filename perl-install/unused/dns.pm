use diagnostics;
use strict;

# This is dumb, but glibc does not like to do hostname lookups w/o libc.so


#TODO TODO
sub doQuery {
#    my ($query, $queryType, $domainName, $ipNum) = @_;
#
#    _res.retry = 2;
#
#    len = res_search(query, C_IN, queryType, (void *) &response,
#		     sizeof(response));
#    if (len <= 0) return -1;
#
#    if (ntohs(response.hdr.rcode) != NOERROR) return -1;
#    ancount = ntohs(response.hdr.ancount);
#    if (ancount < 1) return -1;
#
#    data = response.buf + sizeof(HEADER);
#    end = response.buf + len;
#
#    # skip the question
#    data += dn_skipname(data, end) + QFIXEDSZ;
#
#    # parse the answer(s)
#    while (--ancount >= 0 && data < end) {
#
#      # skip the domain name portion of the RR record
#      data += dn_skipname(data, end);
#
#      # get RR information
#      GETSHORT(type, data);
#      data += INT16SZ; # skipp class
#      data += INT32SZ; # skipp TTL
#      GETSHORT(len,  data);
#
#      if (type == T_PTR) {
#	 # we got a pointer
#	 len = dn_expand(response.buf, end, data, name, sizeof(name));
#	 if (len <= 0) return -1;
#	 if (queryType == T_PTR && domainName) {
#	   # we wanted a pointer
#	   *domainName = malloc(strlen(name) + 1);
#	   strcpy(*domainName, name);
#	   return 0;
#	 }
#      } else if (type == T_A) {
#	 # we got an address
#	 if (queryType == T_A && ipNum) {
#	   # we wanted an address
#	   memcpy(ipNum, data, sizeof(*ipNum));
#	   return 0;
#	 }
#      }
#
#      # move ahead to next RR
#      data += len;
#    }
#
#    return -1;
}

