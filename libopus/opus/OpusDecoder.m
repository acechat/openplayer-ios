/* Takes a opus bitstream from java callbacks from JNI and writes raw stereo PCM to
the jni callbacks. Decodes simple and chained OggOpus files from beginning
to end. */

#import <stdio.h>
#import <stdlib.h>
#import <math.h>
#import <string.h>
#import <ogg/ogg.h>
#import <opus.h>
#import <opus_header.h>

#import "OpusDecoder.h"

/*Define message codes*/
#define NOT_OPUS_HEADER -1
#define CORRUPT_HEADER -2
#define OPUS_DECODE_ERROR -3
#define SUCCESS 0

#define OPUS_HEADERS 2

#define BUFFER_LENGTH 4096

#define COMMENT_MAX_LEN 40

int debug = 0;


void testLib(){
    printf("Lib success");
    fprintf(stderr, "Lib success 2");
}

//Stops the opus data feed
void onStopDecodeFeed(/*jmethodID* stopMethodId*/) {
    //(*env)->CallVoidMethod(env, (*opusDataFeed), (*stopMethodId));
}

//Reads raw opus data from the jni callback
int onReadOpusDataFromOpusDataFeed(/* jmethodID* readOpusDataMethodId, char* buffer, jbyteArray* jByteArrayReadBuffer*/) {
    //Call the read method
    int readByteCount = 0;//(*env)->CallIntMethod(env, (*opusDataFeed), (*readOpusDataMethodId), (*jByteArrayReadBuffer), BUFFER_LENGTH);

    //Don't bother copying, just return 0
    if(readByteCount == 0) return 0;

    //Gets the bytes from the java array and copies them to the opus buffer
    //jbyte* readBytes = (*env)->GetByteArrayElements(env, (*jByteArrayReadBuffer), NULL);
    //memcpy(buffer, readBytes, readByteCount);
    
    //Clean up memory and return how much data was read
    //(*env)->ReleaseByteArrayElements(env, (*jByteArrayReadBuffer), readBytes, JNI_ABORT);

    //Return the amount actually read
    return readByteCount;
}

//Writes the pcm data to the Java layer
void onWritePCMDataFromOpusDataFeed( /*jmethodID* writePCMDataMethodId, ogg_int16_t* buffer, int bytes, jshortArray* jShortArrayWriteBuffer*/) {

    //No data to read, just exit
    //if(bytes == 0) return;

    //Copy the contents of what we're writing to the java short array
    //(*env)->SetShortArrayRegion(env, (*jShortArrayWriteBuffer), 0, bytes, (jshort *)buffer);
    
    //Call the write pcm data method
    //(*env)->CallVoidMethod(env, (*opusDataFeed), (*writePCMDataMethodId), (*jShortArrayWriteBuffer), bytes);
}

//Starts the decode feed with the necessary information about sample rates, channels, etc about the stream
void onStart( /*jmethodID* startMethodId, long sampleRate, long channels, char* vendor,
		char *title, char *artist, char *album, char *date, char *track*/) {
    //Creates a java string for the vendor
    /*jstring vendorString = (*env)->NewStringUTF(env, vendor);
    jstring titleString = (*env)->NewStringUTF(env, title);
    jstring artistString = (*env)->NewStringUTF(env, artist);
    jstring albumString = (*env)->NewStringUTF(env, album);
    jstring dateString = (*env)->NewStringUTF(env, date);
    jstring trackString = (*env)->NewStringUTF(env, track);*/

    //Get decode stream info class and constructor
    //jclass decodeStreamInfoClass = (*env)->FindClass(env, "org/xiph/opus/decoderjni/DecodeStreamInfo");

    /*jmethodID constructor = (*env)->GetMethodID(env, decodeStreamInfoClass, "<init>",
    		"(JJLjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V");

    //Create the decode stream info object
    jobject decodeStreamInfo = (*env)->NewObject(env, decodeStreamInfoClass, constructor, (jlong)sampleRate, (jlong)channels, vendorString,
    		titleString, artistString,albumString,dateString,trackString);

    //Call decode feed onStart
    (*env)->CallVoidMethod(env, (*opusDataFeed), (*startMethodId), decodeStreamInfo);

    //Cleanup decode feed object
    (*env)->DeleteLocalRef(env, decodeStreamInfo);

    //Cleanup java vendor string
    (*env)->DeleteLocalRef(env, vendorString);
    (*env)->DeleteLocalRef(env, titleString);
    (*env)->DeleteLocalRef(env, artistString);
    (*env)->DeleteLocalRef(env, albumString);
    (*env)->DeleteLocalRef(env, dateString);
    (*env)->DeleteLocalRef(env, trackString);*/
}

//Starts reading the header information
void onStartReadingHeader(/*jmethodID* startReadingHeaderMethodId*/) {
    //Call header onStart reading method
    //(*env)->CallVoidMethod(env, (*opusDataFeed), (*startReadingHeaderMethodId));
}


//onStartReadingHeader(env, &opusDataFeed, &startReadingHeaderMethodId);
int initJni(int debug0) {
	debug = debug0;
    return debug;
}


/*Process an Opus header and setup the opus decoder based on it.
  It takes several pointers for header values which are needed
  elsewhere in the code.*/
static OpusDecoder *process_header(ogg_packet *op, int *rate, int *channels, int *preskip, int quiet) {
	int err;
	OpusDecoder *st;
	OpusHeader header;

	if (opus_header_parse(op->packet, op->bytes, &header) == 0) {
        fprintf(stderr, "Cannot parse header");
		return NULL;
	} else
        fprintf(stderr, "Header parsed: ch:%d samplerate:%d", header.channels, header.input_sample_rate);
	*channels = header.channels;

	// validate sample rate: If the rate is unspecified we decode to 48000
	if (!*rate) *rate = header.input_sample_rate;
	if (*rate == 0) *rate = 48000;
	if (*rate < 8000 || *rate > 192000) {
        fprintf(stderr, "Invalid input_rate %d, defaulting to 48000 instead.",*rate);
		*rate = 48000;
	}

	*preskip = header.preskip;
	st = opus_decoder_create(*rate, header.channels, &err); // was 48000
	if (err != OPUS_OK)	{
        fprintf(stderr, "Cannot create decoder: %s", opus_strerror(err));
		return NULL;
	}
	if (!st) {
        fprintf(stderr, "Decoder initialization failed: %s", opus_strerror(err));
		return NULL;
	}

	if (header.gain != 0) {
		/*Gain API added in a newer libopus version, if we don't have it
		 we apply the gain ourselves. We also add in a user provided
		 manual gain at the same time.*/
		int gainadj = (int) header.gain;
		err = opus_decoder_ctl(st, OPUS_SET_GAIN(gainadj));
		if (err != OPUS_OK) {
            fprintf(stderr, "Error setting gain: %s", opus_strerror(err));
            return NULL;
		}
	}

	if (!quiet) {
        fprintf(stderr, "Decoding to %d Hz (%d channels)", *rate, *channels);
		if (header.version != 1)
            fprintf(stderr, "Header v%d",header.version);

		if (header.gain != 0) {
            fprintf(stderr, "Playback gain: %f dB\n", header.gain / 256.);
		}
	}

	return st;
}

// read an int from multiple bytes
#define readint(buf, offset) (((buf[offset + 3] << 24) & 0xff000000) | ((buf[offset + 2] << 16) & 0xff0000) | ((buf[offset + 1] << 8) & 0xff00) | (buf[offset] & 0xff))

#define max(a,b) ({ __typeof__ (a) _a = (a); __typeof__ (b) _b = (b); _a > _b ? _a : _b; })
#define min(a,b) ({ __typeof__ (a) _a = (a); __typeof__ (b) _b = (b); _a < _b ? _a : _b; })


// OpusTags | Len 4B | Vendor String (len) | Len 4B Tags | Len Tag 1 4B | Tag 1 String (Len) | Len Tag 2 4B ..
int process_comments(char *c, int length, char *vendor, char *title,  char *artist, char *album, char *date, char *track, int maxlen) {
	int err = SUCCESS;
    fprintf(stderr, "process_comments called for %d bytes.", length);

	if (length < (8 + 4 + 4)) {
		err = NOT_OPUS_HEADER;
		return err;;
	}
	if (strncmp(c, "OpusTags", 8) != 0) {
		err = NOT_OPUS_HEADER;
		return err;
	}
	c += 8; // skip header
	int len = readint(c, 0);
	c += 4;
	if (len < 0 || len > (length - 16)) {
        fprintf(stderr, "invalid/corrupt comments");
		err = NOT_OPUS_HEADER;
		return err;
	}
	strncpy(vendor, c, min(len, maxlen));

	c += len;
	int fields = readint(c, 0); // the -16 check above makes sure we can read this.
	c += 4;
	length -= 16 + len;
	if (fields < 0 || fields > (length >> 2)) {
        fprintf(stderr, "invalid/corrupt comments");
		err = NOT_OPUS_HEADER;
		return err;
	}
    fprintf(stderr, "Go and read %d fields:", fields);
	int i = 0;
	for (i = 0; i < fields; i++) {
	    if (length < 4){
            fprintf(stderr, "invalid/corrupt comments");
			err = NOT_OPUS_HEADER;
			return err;
	    }
	    len = readint(c, 0);
	    c += 4;
	    length -= 4;
	    if (len < 0 || len > length)
	    {
            fprintf(stderr, "invalid/corrupt comments");
			err = NOT_OPUS_HEADER;
			return err;
	    }
	    char *tmp = (char *)malloc(len + 1); // we also need the ending 0
	    strncpy(tmp, c, len);
	    tmp[len] = 0;
        fprintf(stderr, "Header comment:%d len:%d [%s]", i, len, tmp);
	    free(tmp);

	    // keys we are looking for in the comments
		char keys[5][10] = { "title=", "artist=", "album=", "date=", "track=" };
		char *values[5] = { title, artist, album, date, track }; // put the values in these pointers
	    int j = 0;
	    for (j = 0; j < 5; j++) { // iterate all keys
	    	int keylen = strlen(keys[j]);
	    	if (!strncasecmp(c, keys[j], keylen )) strncpy(values[j], c + keylen, min(len - keylen , maxlen));
	    }
	    /*if (!strncasecmp(c, "title=", 6)) strncpy(title, c + 6, min(len - 6 , maxlen));
	    if (!strncasecmp(c, "artist=", 7)) strncpy(artist, c + 7, min(len - 7 , maxlen));
	    if (!strncasecmp(c, "album=", 6)) strncpy(album, c + 6, min(len - 6 , maxlen));
	    if (!strncasecmp(c, "date=", 5)) strncpy(date, c + 5, min(len - 5 , maxlen));
	    if (!strncasecmp(c, "track=", 6)) strncpy(track, c + 6, min(len - 6 , maxlen));*/

	    c += len;
	    length -= len;
	  }
    return err;
}

// TODO: Florin, make sure we have those pointer at this point
// This is the only function we need ot call, assuming we have the interface already configured
int readDecodeWriteLoop(id<INativeInterface> callback) {
    fprintf(stderr, "startDecoding called, initing buffers");
    
    
    
    //!![callback onReadEncodedData:<#(const char **)#> ofSize:<#(long)#>];

	/*//Create a new java byte array to pass to the opus data feed method
	jbyteArray jByteArrayReadBuffer = (*env)->NewByteArray(env, BUFFER_LENGTH);

	//Create our write buffer
	jshortArray jShortArrayWriteBuffer = (*env)->NewShortArray(env, BUFFER_LENGTH*2);

        //-- get Java layer method pointer --//
	jclass opusDataFeedClass = (*env)->FindClass(env, "org/xiph/opus/decoderjni/DecodeFeed");


	//Find our java method id's we'll be calling
	jmethodID readOpusDataMethodId = (*env)->GetMethodID(env, opusDataFeedClass, "onReadOpusData", "([BI)I");
	jmethodID writePCMDataMethodId = (*env)->GetMethodID(env, opusDataFeedClass, "onWritePCMData", "([SI)V");
	jmethodID startMethodId = (*env)->GetMethodID(env, opusDataFeedClass, "onStart", "(Lorg/xiph/opus/decoderjni/DecodeStreamInfo;)V");
	jmethodID startReadingHeaderMethodId = (*env)->GetMethodID(env, opusDataFeedClass, "onStartReadingHeader", "()V");
	jmethodID stopMethodId = (*env)->GetMethodID(env, opusDataFeedClass, "onStop", "()V");
	//--
     */
    ogg_int16_t convbuffer[BUFFER_LENGTH]; //take 8k out of the data segment, not the stack
    int convsize=BUFFER_LENGTH;
    
    ogg_sync_state   oy; /* sync and verify incoming physical bitstream */
    ogg_stream_state os; /* take physical pages, weld into a logical stream of packets */
    ogg_page         og; /* one Ogg bitstream page. Opus packets are inside */
    ogg_packet       op; /* one raw packet of data for decode */
    

    char *buffer;
    int  bytes;

    // Decode setup
	// 20ms at 48000, TODO 120ms
	#define MAX_FRAME_SIZE      960
	#define OPUS_STACK_SIZE     31684

	// global data

	int frame_size =0;
	OpusDecoder *st = NULL;
	opus_int64 packet_count;
	int stream_init = 0;
	int eos = 0;
	int channels = 0;
	int rate = 0;
	int preskip = 0;
	int gran_offset = 0;
	int has_opus_stream = 0;
	ogg_int32_t opus_serialno = 0;
	int proccessing_page = 0;
	//

	char vendor[COMMENT_MAX_LEN] = {0};
	char title[COMMENT_MAX_LEN] = {0};
	char artist[COMMENT_MAX_LEN] = {0};
	char album[COMMENT_MAX_LEN] = {0};
	char date[COMMENT_MAX_LEN] = {0};
	char track[COMMENT_MAX_LEN] = {0};

    // florin
	//Notify the decode feed we are starting to initialize
    //onStartReadingHeader(&startReadingHeaderMethodId);

    //1
    ogg_sync_init(&oy); // Now we can read pages

    int inited = 0, header = OPUS_HEADERS;

    int err = SUCCESS;
    int i;

    // start source reading / decoding loop
    while (1) {
    	if (err != SUCCESS) {
            fprintf(stderr, "Global loop closing for error: %d", err);
    		break;
    	}

        // READ DATA : submit a 4k block to Ogg layer
        buffer = ogg_sync_buffer(&oy,BUFFER_LENGTH);
        // florin
        //bytes = onReadOpusDataFromOpusDataFeed(env, &opusDataFeed, &readOpusDataMethodId, buffer, &jByteArrayReadBuffer);
        ogg_sync_wrote(&oy,bytes);

        // Check available data
        if (bytes == 0) {
            fprintf(stderr, "Data source finished.");
        	err = SUCCESS;
        	break;
        }

        // loop pages
        while (1) {
        	// exit loop on error
        	if (err != SUCCESS) break;
        	// sync the stream and get a page
        	int result = ogg_sync_pageout(&oy,&og);
        	// need more data, so go to PREVIOUS loop and read more
        	if (result == 0) break;
           	// missing or corrupt data at this page position
           	if (result < 0) {
                fprintf(stderr, "Corrupt or missing data in bitstream; continuing..");
        		continue;
           	}
           	// we finally have a valid page
			if (!inited) {
				ogg_stream_init(&os, ogg_page_serialno(&og));
                fprintf(stderr, "inited stream, serial no: %ld", os.serialno);
				inited = 1;
				// reinit header flag here
				header = OPUS_HEADERS;

			}
			//  add page to bitstream: can safely ignore errors at this point
			if (ogg_stream_pagein(&os, &og) < 0)
                fprintf(stderr, "error 5 pagein");

			// consume all , break for error
			while (1) {
				result = ogg_stream_packetout(&os,&op);

				if(result == 0) break; // need more data so exit and go read data in PREVIOUS loop
				if(result < 0) continue; // missing or corrupt data at this page position , drop here or tolerate error?


				// decode available data
				if (header == 0) {
					int ret = opus_decode(st, (unsigned char*) op.packet, op.bytes, convbuffer, MAX_FRAME_SIZE, 0);

					/*If the decoder returned less than zero, we have an error.*/
					if (ret < 0) {
                        fprintf(stderr, "Decoding error: %s", opus_strerror(ret));
						err = OPUS_DECODE_ERROR;
						break;
					}
					frame_size = (ret < convsize?ret : convsize);
					// florin
                    //onWritePCMDataFromOpusDataFeed(env, &opusDataFeed, &writePCMDataMethodId, convbuffer, channels*frame_size, &jShortArrayWriteBuffer);


				} // decoding done

				// do we need the header? that's the first thing to take
				if (header > 0) {
					if (header == OPUS_HEADERS) { // first header
						//if (op.b_o_s && op.bytes >= 8 && !memcmp(op.packet, "OpusHead", 8)) {
						if (op.bytes < 8 || memcmp(op.packet, "OpusHead", 8) != 0) {
							err = NOT_OPUS_HEADER;
							break;
						}
						// prepare opus structures
						st = process_header(&op, &rate, &channels, &preskip, 0);
					}
					if (header == OPUS_HEADERS -1) { // second and last header, read comments
						// err = we ignore comment errors
						process_comments((char *)op.packet, op.bytes, vendor, title, artist, album, date, track, COMMENT_MAX_LEN);

					}
					// we need to do this 2 times, for all 2 opus headers! add data to header structure

					// signal next header
					header--;

					// we got all opus headers
					if (header == 0) {
                        // florin
						//  header ready , call player to pass stream details and init AudioTrack
						//onStart(env, &opusDataFeed, &startMethodId, rate, channels, vendor, title, artist, album, date, track);
					}
				} // header decoding

				// while packets

				// check stream end
				if (ogg_page_eos(&og)) {
                    fprintf(stderr, "Stream finished.");
					// clean up this logical bitstream;
					ogg_stream_clear(&os);

					// attempt to go for re-initialization until EOF in data source
					err = SUCCESS;

					inited = 0;
					break;
				}
			}
        	// page if
        } // while pages

    }



    // ogg_page and ogg_packet structs always point to storage in libopus.  They're never freed or manipulated directly


    // OK, clean up the framer
    ogg_sync_clear(&oy);

    // Florin
    //onStopDecodeFeed(env, &opusDataFeed, &stopMethodId);

    //Clean up our buffers
    //(*env)->DeleteLocalRef(env, jByteArrayReadBuffer);
    //(*env)->DeleteLocalRef(env, jShortArrayWriteBuffer);

    return err;
}
