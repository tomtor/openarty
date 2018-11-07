////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	simple-ping.c
//
// Project:	OpenArty, an entirely open SoC based upon the Arty platform
//
// Purpose:	To exercise the network port by ...
//
//	1. Pinging another system, at 1PPS
//	2. Replying to ARP requests
//	3. Replying to external 'pings' requests
//
//	To configure this for your network, you will need to adjust the
//	following constants within this file:
//
//	my_ip_addr
//		This is the (fixed) IP address of your Arty board.  The first
//		octet of the IP address is kept in the high order word.
//
//	my_mac_addr	(unsigned long, 64 bits)
//		This is the fixed MAC address of your Arty board.  The first
//		two octets appear in bits 47:32 (MSB #s are high), and the other
//		four in bits 31:0. Since the Arty PHY does not come with a
//		designated MAC address, I generated one for my PHY using
//		/dev/rand.  The key to this, though, is that the second nibble
//		(bits 8..12) in my_mac_addr[0] must be set to 4'h2 to reflect
//		this fact.
//
//	ping_ip_addr
//		This is the IP address of the computer you wish to ping.
//
//	my_ip_router
//		In case the computer you wish to ping is not your
//		router/gateway, and worse that it is not on your network, then
//		you will need to fill this value in with the IP address of a
//		gateway server that is accessable from this network.  Place
//		that IP address into this variable.
//
//	my_ip_mask
//		The IP mask is used to determine what is on your subnet, versus
//		what needs to be sent to your router/gateway.  Set this mask
//		such that a '1' is placed in every network bit of your IP
//		address, and '0' in every host bit.  For me, I am using a
//		network of 192.168.15.x, where x is the computer on the network,
//		so I set this to 0xffffff00.
//
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2015-2016, Gisselquist Technology, LLC
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of  the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory, run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
//
// License:	GPL, v3, as defined and found on www.gnu.org,
//		http://www.gnu.org/licenses/gpl.html
//
//
////////////////////////////////////////////////////////////////////////////////
//
//

#include <stdio.h>

#include "artyboard.h"
#include "zipcpu.h"
#include "zipsys.h"
#define	KTRAPID_SENDPKT	0
#include "etcnet.h"
#include "protoconst.h"
#include "ledcolors.h"
#include "ipcksum.h"
#include "arp.h"

#define	sys	_sys

unsigned	pkts_received = 0, replies_received=0, arp_requests_received=0,
		arp_pkt_count =0, arp_pkt_invalid =0,
		arp_missed_ip = 0, arp_non_broadcast = 0,
		ip_pkts_received = 0, ip_pkts_invalid = 0,
		icmp_echo_requests=0, icmp_invalid= 0,
		ping_reply_address_not_found = 0, ping_replies_sent = 0,
		ping_reply_err = 0, user_tx_packets = 0,
		user_heartbeats = 0;

unsigned long ping_mac_addr;

// These two numbers will allow us to keep track of how many ping's we've
// sent and how many we've received the returns for.
unsigned	ping_tx_count = 0, ping_rx_count = 0;

int SIZE_LONG= sizeof(unsigned long);

// This is a cheater's approach to knowing what IP to ping: we pre-load the
// program with both the IP address to ping, as well as the MAC address
// associated with that IP address.  Future implementations will need to
// 1. Look up the MAC address of the device we wish to ping (assuming our
//	subnet), or
// 2. Later, check if the IP address is not on our subnet, and if not then
//	look up the MAC address of the router and use that MAC address when
//	sending (no change to the IP)
unsigned	ping_ip_addr  = IPADDR(192,168,0,3);
unsigned long	ping_mac_addr = 0x309c23618084;

// My network ID.  The 192.168.15 part comes from the fact that this is a
// local network.  The .22 (last octet) is due to the fact that this is
// an unused ID on my network.
unsigned	my_ip_addr  = DEFAULTIP;
// Something from /dev/rand
//	Only ... the second nibble must be two.  Hence we start with d(2)d8.
unsigned long	my_mac_addr = DEFAULTMAC, router_mac_addr = 0;
unsigned	my_ip_mask = LCLNETMASK,
		my_ip_router = DEFAULT_ROUTERIP;

unsigned	pkt_id = 0;

///////////
//
//
// User tasks and functions (excluding ARP)
//
//
///////////


//
// We'll give our user 64kW of global variables
//
#define	USER_STACK_SIZE	1024 // 4096
int	user_stack[USER_STACK_SIZE];
const int *user_sp = &user_stack[USER_STACK_SIZE];


void	uping_reply(unsigned ipaddr, unsigned *icmp_request) {
	unsigned	pkt[512]; // [2048];
	unsigned long	hwaddr;
	int		maxsz = 2048;

	maxsz = 1<<((sys->io_enet.n_rxcmd>>24)&0x0f);
	if (maxsz > 2048)
		maxsz = 2048;
	int pktln = (icmp_request[0] & 0x0ffff)+8, pktlnw = (pktln+3)>>2;

	if (arp_lookup(ipaddr, &hwaddr)!=0) {
		// Couldn't find the address -- don't reply, but send an arp
		// request.
		//
		// ARP request is automatic when the address isn't found,
		// and done by the arp_lookup.
		ping_reply_address_not_found++;
	} else if ((pktlnw < maxsz)
			&&((icmp_request[0]>>24)==0x045)) {
		int		id;

		pkt[0] = (unsigned)(hwaddr>>16);
		pkt[1] = ((unsigned)(hwaddr<<16))|ETHERTYPE_IP;
		pkt[2] = icmp_request[0] & 0xff00ffff;
		id = pkt_id + sys->io_b.i_tim.sub;
		pkt[3] = (id&0x0ffff)<<16; // no fragments
		pkt[4] = 0xff010000;//No flags,frag offset=0,ttl=0,proto=1(ICMP)
		pkt[5] = icmp_request[4];	// Swap sender and receiver
		pkt[6] = icmp_request[3];
		for(int k=7; k<pktlnw; k++)
			pkt[k] = icmp_request[k-2];
		pkt[7] = 0;

		if ((pktln & 3)!=0)
			pkt[pktlnw-1] &= ~((1<<((4-(pktln&3))<<3))-1);

		// Now, let's go fill in the IP and ICMP checksums
		pkt[4] |= ipcksum(5, &pkt[2]);

		pkt[7] &= 0xffff0000;
		pkt[7] |= ipcksum(pktlnw-7, &pkt[7]);

		ping_replies_sent++;

		syscall(KTRAPID_SENDPKT,0,(unsigned)pkt, pktln);
	} else
		ping_reply_err ++;
}

unsigned	rxpkt[2048];

//void user_task(void) __attribute__((section(".fastcode")));
void	user_task(void) {
	unsigned	rtc = sys->io_rtc.r_clock;

	while(1) {
		do {
			unsigned long	mac;

			// Rate limit our ARP searching to one Hz
			rtc = sys->io_rtc.r_clock;

			if (arp_lookup(ping_ip_addr, &ping_mac_addr) == 0)
				arp_lookup(my_ip_router, &mac);

			while(((sys->io_enet.n_rxcmd & ENET_RXAVAIL)==0)
					&&(sys->io_rtc.r_clock == rtc))
				user_heartbeats++;
		} while((sys->io_enet.n_rxcmd & ENET_RXAVAIL)==0);

		// Okay, now we have a receive packet ... let's process it
		int	etype = sys->io_enet_rx[1] & 0x0ffff;
		unsigned *epayload; //  = (unsigned *)&sys->io_enet_rx[2];
		int	invalid = 0;
		int	ln, rxcmd = sys->io_enet.n_rxcmd;

		ln = sys->io_enet.n_rxcmd & 0x07ff;
		for(int k=0; k<(ln+3)>>2; k++)
			rxpkt[k] = sys->io_enet_rx[k];
		epayload = &rxpkt[2];
		sys->io_enet.n_rxcmd = ENET_RXCLR|ENET_RXCLRERR;

		pkts_received++;

		if (etype == ETHERTYPE_IP) {
			unsigned *ip = epayload,
				*ippayload = &ip[(ip[0]>>24)&0x0f];

			if (((ip[0]>>28)&15)!=4)
				invalid = 1;
			else if (ip[1] & 0x0bfff)
				// Packet is fragmented--toss it out
				invalid = 1;
			else if (ip[4] != my_ip_addr)
				invalid = 1;

			ip_pkts_received += (invalid^1);
			ip_pkts_invalid  += (invalid);

			unsigned ipproto = (ip[2]>>16)&0x0ff;
			if((invalid==0)&&(ipproto == IPPROTO_ICMP)) {
				unsigned icmp_type = ippayload[0]>>24;
				if (icmp_type == ICMP_ECHOREPLY) {
					// We got our ping response
					sys->io_b.i_clrled[3] = LEDC_GREEN;
					sys->io_b.i_leds = 0x80;
					ping_rx_count++;
				} else if (icmp_type == ICMP_ECHO) {
					// Someone is pinging us
					uping_reply(ip[3],ip);
					icmp_echo_requests++;
				} else
					icmp_invalid++;
			} else if(ipproto == IPPROTO_UDP) {
				// UDP Here?
				if (invalid) {
				    //printf("BC UDP\n");
					//sys->io_enet.n_rxcmd = ENET_RXCLRERR|ENET_RXCLR;
				    send_ping();
				} else {
				    void reply_udp(unsigned *pkt);
				    reply_udp(ip);}
			}
		} else if (etype == ETHERTYPE_ARP) {
			arp_pkt_count++;
			if (epayload[0] != 0x010800) {
				invalid = 1;
				arp_pkt_invalid++;
			} else if ((epayload[1] == 0x06040001)
					&&(rxcmd & ENET_RXBROADCAST)) {
				//printf("ARP-REQ\n");
				if (epayload[6] == my_ip_addr) {
					printf("MINE\n");
					unsigned sha[2], // Senders HW address
					sip, // Senders IP address
					dip; // Desired IP address
					sha[0] = epayload[2];
					sha[1] = epayload[3]>>16;
					sha[1] |= sha[0]<<16;
					sha[0] >>= 16;
					sip = (epayload[3]<<16)|(epayload[4]>>16);
					arp_requests_received++;
					send_arp_reply(sha[0], sha[1], sip);
				} else
					send_ping(); // clear ethernet
			} else if ((epayload[1] == 0x06040002) // Reply
				&&((rxcmd & ENET_RXBROADCAST)==0)
				&&(epayload[6] == my_ip_addr)) {
				printf("ARP-ADD\n");
				unsigned	sip;
				unsigned long	sha;

				sha = *(unsigned long *)(&epayload[2]);
				sha >>= 16;
				sip = (epayload[3]<<16)|(epayload[4]>>16);
				if (sip == ping_ip_addr)
					ping_mac_addr = sha;
				arp_table_add(sip, sha);
			}
		}
	}
}


///////////
//
//
// Supervisor tasks and functions
//
//
///////////

void wait_busy()
{
    // If the network is busy transmitting, wait for it to finish
    if (sys->io_enet.n_txcmd & ENET_TXBUSY) {
    	//printf("W");
        while(sys->io_enet.n_txcmd & ENET_TXBUSY)
            ; // printf(".");
        //printf("\n");
    }
}

//void reply_udp(unsigned *ip) __attribute__((section(".fastcode")));
void reply_udp(unsigned *ip)
{
	//wait_busy();
//	static unsigned udp;
//	printf("R %u\n", ++udp);

    // Form a packet to transmit
    //unsigned *pkt = (unsigned *)&sys->io_enet_tx;
	char buf[1100];
	//memset(buf, sizeof(buf), 0);
	unsigned *pkt= (unsigned*)buf;

    pkt[0] = (ping_mac_addr>>16);
    pkt[1] = ((unsigned)(ping_mac_addr<<16))|ETHERTYPE_IP;
    pkt[2] = ip[0];
    pkt[3] = ip[1];
    //printf("%08x\n", ip[2]);
    pkt[4] = ip[2] & 0xFFFF0000; // Has old header checksum
    pkt[5] = my_ip_addr;
    pkt[6] = ping_ip_addr; // ip[3]; // dest = old source

    if (((ip[0] >> 24) & 0xF) > 5) {
        printf("Options: %d %08x!\r\n", ((ip[0] >> 24) & 0xF) > 5, ip[0]);
        return;
    }

    pkt[7] = (ip[5] >> 16) | (7777 << 16); // UDP ports
    pkt[8] = (ip[6] & 0xFFFF0000); // length and checksum
    //printf("%08x\n", ip[6]);
    //pkt[9] = ip[7]; // first data
    for (int i= 0; i < 257; i++)
    	pkt[9+i]= ip[7+i];

    // Calculate the IP header checksum
    pkt[4] |= ipcksum(5, &pkt[2]);

    // Calculate the PING payload checksum
    //pkt[7] &= 0xffff0000;
    //pkt[7] |= ipcksum(2, &pkt[7]);

    // Finally, send the packet -- 9*4 = our total number of octets
    //sys->io_enet.n_txcmd = ENET_TXCMD((9+257)*4);

    syscall(KTRAPID_SENDPKT,0,(unsigned)pkt, (9+257)*4);
}


void	send_ping(void) {
	unsigned *pkt;

	// If we don't know our destination MAC address yet, just return
	if (ping_mac_addr==0) {
		sys->io_b.i_clrled[1] = LEDC_YELLOW;
		return;
	}

	wait_busy();

	// Form a packet to transmit
	pkt = (unsigned *)&sys->io_enet_tx;
	pkt[0] = (ping_mac_addr>>16);
	pkt[1] = ((unsigned)(ping_mac_addr<<16))|ETHERTYPE_IP;
	pkt[2] = 0x4500001c;
	pkt_id += BIG_PRIME; // A BIG prime number
	pkt[3] = (pkt_id&0x0ffff)<<16;;
	pkt[4] = 0x80010000; // No flags, ragment offset = 0, ttl=0, proto=1(ICMP)
	pkt[5] =   my_ip_addr;
	pkt[6] = ping_ip_addr;
	// Ping payload: type = 0x08 (PING, the response will be zero)
	//	CODE = 0
	//	Checksum will be filled in later
	pkt[7] = 0x08000000;
	pkt_id += BIG_PRIME;
	pkt[8] = (pkt_id + BIG_PRIME);

	// Calculate the IP header checksum
	pkt[4] |= ipcksum(5, &pkt[2]);

	// Calculate the PING payload checksum
	pkt[7] &= 0xffff0000;
	pkt[7] |= ipcksum(2, &pkt[7]);

	// Finally, send the packet -- 9*4 = our total number of octets
	sys->io_enet.n_txcmd = ENET_TXCMD(9*4);

	ping_tx_count++;
}


int	heartbeats = 0, subbeats = 0, gbl_picv = 0;
int main(int argc, char **argv) {
	unsigned	user_context[16];
	int		lastpps;

	for(int i=0; i<16; i++)
		user_context[i] = 0;
	user_context[13] = (unsigned)user_sp;
	user_context[15] = (unsigned)user_task;
	restore_context(user_context);

	printf("GO!\n");

	init_arp_table();

	for(int i=0; i<4; i++)
		sys->io_b.i_clrled[i] = LEDC_BRIGHTRED;
	sys->io_b.i_leds = 0x0ff;

	// Start up the network interface
	if ((sys->io_enet.n_txcmd & ENET_RESET)!=0)
		sys->io_enet.n_txcmd = 0; // Turn on all our features
	{
		volatile unsigned long *emac = (volatile unsigned long *)&sys->io_enet.n_mac;
		*emac = my_mac_addr;
	}

	// Turn off our right-hand LED, first part of startup is complete
	sys->io_b.i_leds = 0x010;
	// Turn our first CLR LED green as well
	sys->io_b.i_clrled[0] = LEDC_GREEN;

	// Set our timer to have us send a ping 1/sec
	zip->z_tma = CLOCKFREQ_HZ | TMR_INTERVAL;

	sys->io_enet.n_rxcmd = ENET_RXCLRERR|ENET_RXCLR;

	while(1) {
		unsigned	picv, bmsr;

		heartbeats++;

		// Wait while the link is being negotiated
		// --- Read the MDIO status register
		bmsr = sys->io_netmdio.e_v[MDIO_BMSR];
		if ((bmsr & 4)==0) {
			// Link is down, do nothing this time through
			sys->io_b.i_clrled[1] = LEDC_BRIGHTRED;
			sys->io_b.i_clrled[2] = LEDC_BRIGHTRED;
			sys->io_b.i_clrled[3] = LEDC_BRIGHTRED;
		} else {
			sys->io_b.i_leds = 0x020;
			sys->io_b.i_clrled[1] = LEDC_GREEN;
			send_ping();
			sys->io_b.i_clrled[2] = LEDC_BRIGHTRED; // Have we received a response?
			sys->io_b.i_clrled[3] = LEDC_BRIGHTRED; // Was it our ping response?
		}

		// Clear any timer or PPS interrupts, disable all others
		zip->z_pic = DALLPIC;
		zip->z_pic = EINT(SYSINT_TMA|SYSINT_PPS|SYSINT_ENETRX);
		do {
			if ((zip->z_pic & INTNOW)==0)
				zip_rtu();
			subbeats++;

			picv = zip->z_pic;
			gbl_picv = picv;

			// Clear the ints we just saw.  Warning, though, we'll
			// need to re-enable them later
			zip->z_pic = (picv & 0x0ffff);

			if (zip_ucc() & CC_FAULT) {
				sys->io_b.i_leds = 0x0ff;
				sys->io_b.i_clrled[0] = LEDC_BRIGHTRED;
				sys->io_b.i_clrled[1] = LEDC_BRIGHTRED;
				sys->io_b.i_clrled[2] = LEDC_BRIGHTRED;
				sys->io_b.i_clrled[3] = LEDC_BRIGHTRED;
				zip_halt();
			} else if (zip_ucc() & CC_TRAP) {
				save_context((int *)user_context);
				// R0 = return address
				// R1 = Trap ID, write or send
				// R2 = FD, or socketFD
				// R3 = buffer
				// R4 = count
				// R5 = (flags, i socket)
				unsigned *sptr = (void *)user_context[3], ln;
				ln = user_context[4];
				while(sys->io_enet.n_txcmd & ENET_TXBUSY)
					;
				if (ln < 1400) {
					for(int i=0; i<(ln+3)>>2; i++)
						sys->io_enet_tx[i] = *sptr++;
					sys->io_enet.n_txcmd = ENET_TXCMD(ln);

					user_tx_packets++;
					// (Re-)Enable the transmit complete
					// interrupt
					//
					// At this point, we are also ready to
					// receive another packet
					zip->z_pic = EINT(SYSINT_ENETTX|SYSINT_ENETRX);
				}

				user_context[14] &= ~CC_TRAP;
				restore_context(user_context);
			} else if ((picv & INTNOW)==0) {
				sys->io_b.i_leds = 0x0ff;
				sys->io_b.i_clrled[0] = LEDC_BRIGHTRED;
				sys->io_b.i_clrled[1] = LEDC_WHITE;
				sys->io_b.i_clrled[2] = LEDC_BRIGHTRED;
				sys->io_b.i_clrled[3] = LEDC_BRIGHTRED;
				zip_halt();
			} else if ((picv & DINT(SYSINT_TMA))==0) {
				sys->io_b.i_leds = 0x0ff;
				sys->io_b.i_clrled[0] = LEDC_BRIGHTRED;
				sys->io_b.i_clrled[1] = LEDC_BRIGHTRED;
				sys->io_b.i_clrled[2] = LEDC_WHITE;
				sys->io_b.i_clrled[3] = LEDC_BRIGHTRED;
				zip_halt();
			} else if ((picv & DINT(SYSINT_PPS))==0) {
				sys->io_b.i_leds = 0x0ff;
				sys->io_b.i_clrled[0] = LEDC_BRIGHTRED;
				sys->io_b.i_clrled[1] = LEDC_BRIGHTRED;
				sys->io_b.i_clrled[2] = LEDC_BRIGHTRED;
				sys->io_b.i_clrled[3] = LEDC_WHITE;
				zip_halt();
			} if (picv & SYSINT_ENETRX) {
				// This will not clear until the packet has
				// been removed and the interface reset.  For
				// now, just double check that the interrupt
				// has been disabled.
				if (picv&(DINT(SYSINT_ENETRX))) {
					zip->z_pic = DINT(SYSINT_ENETRX);
					sys->io_b.i_leds = 0x040;
					sys->io_b.i_clrled[2] = LEDC_GREEN;
				}
			} else
				zip->z_pic = EINT(SYSINT_ENETRX);
			if (picv & SYSINT_ENETTX) {
				// This will also likewise not clear until a
				// packet has been queued up for transmission.
				// Hence, let's just disable the interrupt.
				if (picv&(DINT(SYSINT_ENETTX)))
					zip->z_pic = DINT(SYSINT_ENETTX);
			} else
				zip->z_pic = EINT(SYSINT_ENETTX);
			// Make certain interrupts remain enabled
			zip->z_pic = EINT(SYSINT_TMA|SYSINT_PPS);

			if (picv & SYSINT_TMA) {
				if (lastpps==1)
					lastpps = 2;
				else {
					picv &= ~SYSINT_TMA;
					lastpps = 0;
				}
			}
		} while((picv & (SYSINT_TMA|SYSINT_PPS))==0);
		if (picv & SYSINT_PPS) {
			lastpps = 1;
			zip->z_tma = CLOCKFREQ_HZ | TMR_INTERVAL;
		}
	}
}
