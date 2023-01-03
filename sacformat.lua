local ffi = require 'ffi'

-- sac of shit 
-- I could define this as enums but why mess up the ffi.C namespace 
local sac = {}

sac.REGCONV = 100

sac.SACHEADERLEN = 632  -- SAC header length in bytes (only version 6?) 
sac.NUMFLOATHDR = 70    -- Number of float header variables, 4 bytes each 
sac.NUMINTHDR = 40      -- Number of integer header variables, 4 bytes each 
sac.NUMSTRHDR = 23      -- Number of string header variables, 22x8 bytes + 1x16 bytes 

-- Undefined values for float, integer and string header variables 
sac.FUNDEF = -12345.0
sac.IUNDEF = -12345
-- #define SUNDEF "-12345  " 

-- definitions of constants for SAC enumerated data values 
sac.IREAL = 0		
sac.ITIME = 1			-- file: time series data    
sac.IRLIM = 2			-- file: real&imag spectrum  
sac.IAMPH = 3			-- file: ampl&phas spectrum  
sac.IXY = 4				-- file: gen'l x vs y data   
sac.IUNKN = 5			-- x data: unknown type      
						-- zero time: unknown        
						-- event type: unknown       
sac.IDISP = 6			-- x data: displacement (nm) 
sac.IVEL = 7			-- x data: velocity (nm/sec) 
sac.IACC = 8			-- x data: accel (cm/sec/sec)
sac.IB = 9				-- zero time: start of file  
sac.IDAY = 10			-- zero time: 0000 of GMT day
sac.IO = 11				-- zero time: event origin   
sac.IA = 12				-- zero time: 1st arrival    
sac.IT0 = 13			-- zero time: user timepick 0
sac.IT1 = 14			-- zero time: user timepick 1
sac.IT2 = 15			-- zero time: user timepick 2
sac.IT3 = 16			-- zero time: user timepick 3
sac.IT4 = 17			-- zero time: user timepick 4
sac.IT5 = 18			-- zero time: user timepick 5
sac.IT6 = 19			-- zero time: user timepick 6
sac.IT7 = 20			-- zero time: user timepick 7
sac.IT8 = 21			-- zero time: user timepick 8
sac.IT9 = 22			-- zero time: user timepick 9
sac.IRADNV = 23			
sac.ITANNV = 24			
sac.IRADEV = 25			
sac.ITANEV = 26			
sac.INORTH = 27			
sac.IEAST = 28			
sac.IHORZA = 29			
sac.IDOWN = 30			
sac.IUP = 31			
sac.ILLLBB = 32			
sac.IWWSN1 = 33			
sac.IWWSN2 = 34			
sac.IHGLP = 35			
sac.ISRO = 36			

-- Source types 
sac.INUCL = 37			-- event type: nuclear shot  
sac.IPREN = 38			-- event type: nuke pre-shot 
sac.IPOSTN = 39			-- event type: nuke post-shot
sac.IQUAKE = 40			-- event type: earthquake    
sac.IPREQ = 41			-- event type: foreshock     
sac.IPOSTQ = 42			-- event type: aftershock    
sac.ICHEM = 43			-- event type: chemical expl 
sac.IOTHER = 44			-- event type: other source  
sac.IQB = 72			-- Quarry Blast or mine expl. confirmed by quarry 
sac.IQB1 = 73  			-- Quarry or mine blast with designed shot information-ripple fired 
sac.IQB2 = 74  			-- Quarry or mine blast with observed shot information-ripple fired 
sac.IQBX = 75  			-- Quarry or mine blast - single shot 
sac.IQMT = 76  			-- Quarry or mining-induced events: tremors and rockbursts 
sac.IEQ = 77  			-- Earthquake 
sac.IEQ1 = 78  			-- Earthquakes in a swarm or aftershock sequence 
sac.IEQ2 = 79  			-- Felt earthquake 
sac.IME = 80  			-- Marine explosion 
sac.IEX = 81  			-- Other explosion 
sac.INU = 82  			-- Nuclear explosion 
sac.INC = 83  			-- Nuclear cavity collapse 
sac.IO_ = 84  			-- Other source of known origin 
sac.IL = 85  			-- Local event of unknown origin 
sac.IR = 86  			-- Regional event of unknown origin 
sac.IT = 87  			-- Teleseismic event of unknown origin 
sac.IU = 88  			-- Undetermined or conflicting information  
sac.IEQ3 = 89  			-- Damaging earthquake 
sac.IEQ0 = 90  			-- Probable earthquake 
sac.IEX0 = 91  			-- Probable explosion 
sac.IQC = 92  			-- Mine collapse 
sac.IQB0 = 93  			-- Probable Mine Blast 
sac.IGEY = 94  			-- Geyser 
sac.ILIT = 95  			-- Light 
sac.IMET = 96  			-- Meteoric Event 
sac.IODOR = 97  		-- Odors 
sac.IOS = 103 			-- Other source: Known origin

						-- data quality: other problm
sac.IGOOD = 45			-- data quality: good        
sac.IGLCH = 46			-- data quality: has glitches
sac.IDROP = 47			-- data quality: has dropouts
sac.ILOWSN = 48			-- data quality: low s/n     

sac.IRLDTA = 49			-- data is real data         
sac.IVOLTS = 50			-- file: velocity (volts)    

-- Magnitude type and source 
sac.IMB = 52           	-- Bodywave Magnitude */ 
sac.IMS = 53           	-- Surface Magnitude 
sac.IML = 54           	-- Local Magnitude  */ 
sac.IMW = 55           	-- Moment Magnitude 
sac.IMD = 56           	-- Duration Magnitude 
sac.IMX = 57           	-- User Defined Magnitude 
sac.INEIC = 58                      
sac.IPDEQ = 59                      
sac.IPDEW = 60                      
sac.IPDE = 61                      

sac.IISC = 62                      
sac.IREB = 63                      
sac.IUSGS = 64                      
sac.IBRK = 65                      
sac.ICALTECH = 66                    
sac.ILLNL = 67                      
sac.IEVLOC = 68                      
sac.IJSOP = 69                      
sac.IUSER = 70                      
sac.IUNKNOWN = 71                    

ffi.cdef[[
/* SAC header structure as it exists in binary SAC files */
struct SACHeader {
	float	delta;			/* RF time increment, sec    */
	float	depmin;			/*    minimum amplitude      */
	float	depmax;			/*    maximum amplitude      */
	float	scale;			/*    amplitude scale factor */
	float	odelta;			/*    observed time inc      */
	float	b;			/* RD initial value, time    */
	float	e;			/* RD final value, time      */
	float	o;			/*    event start, sec < nz. */
	float	a;			/*    1st arrival time       */
	float	fmt;			/*    internal use           */
	float	t0;			/*    user-defined time pick */
	float	t1;			/*    user-defined time pick */
	float	t2;			/*    user-defined time pick */
	float	t3;			/*    user-defined time pick */
	float	t4;			/*    user-defined time pick */
	float	t5;			/*    user-defined time pick */
	float	t6;			/*    user-defined time pick */
	float	t7;			/*    user-defined time pick */
	float	t8;			/*    user-defined time pick */
	float	t9;			/*    user-defined time pick */
	float	f;			/*    event end, sec > nz    */
	float	resp0;			/*    instrument respnse parm*/
	float	resp1;			/*    instrument respnse parm*/
	float	resp2;			/*    instrument respnse parm*/
	float	resp3;			/*    instrument respnse parm*/
	float	resp4;			/*    instrument respnse parm*/
	float	resp5;			/*    instrument respnse parm*/
	float	resp6;			/*    instrument respnse parm*/
	float	resp7;			/*    instrument respnse parm*/
	float	resp8;			/*    instrument respnse parm*/
	float	resp9;			/*    instrument respnse parm*/
	float	stla;			/*  T station latititude     */
	float	stlo;			/*  T station longitude      */
	float	stel;			/*  T station elevation, m   */
	float	stdp;			/*  T station depth, m      */
	float	evla;			/*    event latitude         */
	float	evlo;			/*    event longitude        */
	float	evel;			/*    event elevation        */
	float	evdp;			/*    event depth            */
	float	mag;			/*    reserved for future use*/
	float	user0;			/*    available to user      */
	float	user1;			/*    available to user      */
	float	user2;			/*    available to user      */
	float	user3;			/*    available to user      */
	float	user4;			/*    available to user      */
	float	user5;			/*    available to user      */
	float	user6;			/*    available to user      */
	float	user7;			/*    available to user      */
	float	user8;			/*    available to user      */
	float	user9;			/*    available to user      */
	float	dist;			/*    stn-event distance, km */
	float	az;			/*    event-stn azimuth      */
	float	baz;			/*    stn-event azimuth      */
	float	gcarc;			/*    stn-event dist, degrees*/
	float	sb;			/*    internal use           */
	float	sdelta;			/*    internal use           */
	float	depmen;			/*    mean value, amplitude  */
	float	cmpaz;			/*  T component azimuth     */
	float	cmpinc;			/*  T component inclination */
	float	xminimum;		/*    reserved for future use*/
	float	xmaximum;		/*    reserved for future use*/
	float	yminimum;		/*    reserved for future use*/
	float	ymaximum;		/*    reserved for future use*/
	float	unused6;		/*    reserved for future use*/
	float	unused7;		/*    reserved for future use*/
	float	unused8;		/*    reserved for future use*/
	float	unused9;		/*    reserved for future use*/
	float	unused10;		/*    reserved for future use*/
	float	unused11;		/*    reserved for future use*/
	float	unused12;		/*    reserved for future use*/
	int32_t nzyear;			/*  F zero time of file, yr  */
	int32_t nzjday;			/*  F zero time of file, day */
	int32_t nzhour;			/*  F zero time of file, hr  */
	int32_t nzmin;			/*  F zero time of file, min */
	int32_t nzsec;			/*  F zero time of file, sec */
	int32_t nzmsec;			/*  F zero time of file, millisec*/
	int32_t nvhdr;			/*    internal use (version) */
	int32_t norid;			/*    origin ID              */
	int32_t nevid;			/*    event ID               */
	int32_t npts;			/* RF number of samples      */
	int32_t nsnpts;			/*    internal use           */
	int32_t nwfid;			/*    waveform ID            */
	int32_t nxsize;			/*    reserved for future use*/
	int32_t nysize;			/*    reserved for future use*/
	int32_t unused15;		/*    reserved for future use*/
	int32_t iftype;			/* RA type of file          */
	int32_t idep;			/*    type of amplitude      */
	int32_t iztype;			/*    zero time equivalence  */
	int32_t unused16;		/*    reserved for future use*/
	int32_t iinst;			/*    recording instrument   */
	int32_t istreg;			/*    stn geographic region  */
	int32_t ievreg;			/*    event geographic region*/
	int32_t ievtyp;			/*    event type             */
	int32_t iqual;			/*    quality of data        */
	int32_t isynth;			/*    synthetic data flag    */
	int32_t imagtyp;		/*    reserved for future use*/
	int32_t imagsrc;		/*    reserved for future use*/
	int32_t unused19;		/*    reserved for future use*/
	int32_t unused20;		/*    reserved for future use*/
	int32_t unused21;		/*    reserved for future use*/
	int32_t unused22;		/*    reserved for future use*/
	int32_t unused23;		/*    reserved for future use*/
	int32_t unused24;		/*    reserved for future use*/
	int32_t unused25;		/*    reserved for future use*/
	int32_t unused26;		/*    reserved for future use*/
	int32_t leven;			/* RA data-evenly-spaced flag*/
	int32_t lpspol;			/*    station polarity flag  */
	int32_t lovrok;			/*    overwrite permission   */
	int32_t lcalda;			/*    calc distance, azimuth */
	int32_t unused27;		/*    reserved for future use*/
	char	kstnm[8];		/*  F station name           */
	char	kevnm[16];		/*    event name             */
	char	khole[8];		/*    man-made event name    */
	char	ko[8];			/*    event origin time id   */
	char	ka[8];			/*    1st arrival time ident */
	char	kt0[8];			/*    time pick 0 ident      */
	char	kt1[8];			/*    time pick 1 ident      */
	char	kt2[8];			/*    time pick 2 ident      */
	char	kt3[8];			/*    time pick 3 ident      */
	char	kt4[8];			/*    time pick 4 ident      */
	char	kt5[8];			/*    time pick 5 ident      */
	char	kt6[8];			/*    time pick 6 ident      */
	char	kt7[8];			/*    time pick 7 ident      */
	char	kt8[8];			/*    time pick 8 ident      */
	char	kt9[8];			/*    time pick 9 ident      */
	char	kf[8];			/*    end of event ident     */
	char	kuser0[8];		/*    available to user      */
	char	kuser1[8];		/*    available to user      */
	char	kuser2[8];		/*    available to user      */
	char	kcmpnm[8];		/*  F component name         */
	char	knetwk[8];		/*    network name           */
	char	kdatrd[8];		/*    date data read         */
	char	kinst[8];		/*    instrument name        */
};
typedef struct SACHeader SACHeader_t;
]]

--[[
/* A SAC header null value initializer 
 * Usage: struct SACHeader sh = NullSACHeader; */
#define NullSACHeader {                                                          \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345.0, -12345.0, -12345.0, -12345.0, -12345.0,                        \
        -12345, -12345, -12345, -12345, -12345,                                  \
        -12345, -12345, -12345, -12345, -12345,                                  \
        -12345, -12345, -12345, -12345, -12345,                                  \
        -12345, -12345, -12345, -12345, -12345,                                  \
        -12345, -12345, -12345, -12345, -12345,                                  \
        -12345, -12345, -12345, -12345, -12345,                                  \
        -12345, -12345, -12345, -12345, -12345,                                  \
        -12345, -12345, -12345, -12345, -12345,                                  \
        { '-','1','2','3','4','5',' ',' ' },                                     \
        { '-','1','2','3','4','5',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ' },     \
        { '-','1','2','3','4','5',' ',' ' },{ '-','1','2','3','4','5',' ',' ' }, \
        { '-','1','2','3','4','5',' ',' ' },{ '-','1','2','3','4','5',' ',' ' }, \
        { '-','1','2','3','4','5',' ',' ' },{ '-','1','2','3','4','5',' ',' ' }, \
        { '-','1','2','3','4','5',' ',' ' },{ '-','1','2','3','4','5',' ',' ' }, \
        { '-','1','2','3','4','5',' ',' ' },{ '-','1','2','3','4','5',' ',' ' }, \
        { '-','1','2','3','4','5',' ',' ' },{ '-','1','2','3','4','5',' ',' ' }, \
        { '-','1','2','3','4','5',' ',' ' },{ '-','1','2','3','4','5',' ',' ' }, \
        { '-','1','2','3','4','5',' ',' ' },{ '-','1','2','3','4','5',' ',' ' }, \
        { '-','1','2','3','4','5',' ',' ' },{ '-','1','2','3','4','5',' ',' ' }, \
        { '-','1','2','3','4','5',' ',' ' },{ '-','1','2','3','4','5',' ',' ' }, \
        { '-','1','2','3','4','5',' ',' ' }                                      \
};
]]

return sac
