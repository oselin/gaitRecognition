classdef LpmsBT < handle
%% ------------------------------------------------------------------------
%   GAIT RECOGNITION BASED ON IMU DATA AND ML ALGORITHM
%   LIBRARY TO MANAGE COMMUNICATION WITH LPMSB2 SENSOR
%   Albi Matteo, Cardone Andrea, Oselin Pierfrancesco
%
%   Based on the library:
%       https://bitbucket.org/lpresearch/lpsensormatlab/src/master/lpms.m
%       Lpms class to interface with LpmsSensors
%
%       Known Issues:
%       - Serial Interrupt routine blocks main processing thread
%           when transferring at data rate > 100Hz 
%
%       TODO: 
%       - Implement 16bit data parsing
%
%
%       Author: H.E.Yap
%       Date: 2016/07/19    
%       Revision: 0.1 
%       Copyright: LP-Research Inc. 2016
%       
%
%   NB: You must pair the device with your computer first before connecting 
%   to it 
%
%   GENERAL: to read an answer an interrupt like approach is used. To 
%   enable an interrupt the function configureCallback is used. To set the 
%   interrupt is passed the number of bytes the programm must receive to 
%   trigger the interrupt and the function to call when the interrupt is 
%   triggered. The function called is readCallbackFcn: it reads all the 
%   data available on the input buffer and parses it by calling the parse 
%   function. The parse function reads each byte until a full packet is read, 
%   extracting all the needed info like packet function, data length and 
%   raw data, saving them in object variables. Then the parseFunction 
%   method is called, checking the packet function code and executing the 
%   right instructions according to it (parsing data in case of get 
%   instruction, check ack in case of set instruction).
%   After all data in input buffer has been read, the program proceeds with
%   normal execution.
%   NB in case of streaming mode, the interrupt is triggere every time a
%   packet is received.
%
% TODO: 
% - Implement 16bit data parsing
% - Implement get serail number
% - Implement get firmware info
%
% -------------------------------------------------------------------------
    
    properties (Constant)
        %the name the code will loking for when performing connection
        DEV_NAME = "LPMSB2";
        
        %definition of parse phases in a packet, read:
        PACKET_ADDRESS0     = 0; %1st byte address
        PACKET_ADDRESS1     = 1; %2nd byte address
        PACKET_FUNCTION0    = 2; %1st byte function identifier 
        PACKET_FUNCTION1    = 3; %2nd byte function identifier
        PACKET_LENGTH0      = 4; %1st byte number of byte in the packet 
        PACKET_LENGTH1      = 5; %2nd byte number of byte in the packet 
        PACKET_RAW_DATA     = 6; %data
        PACKET_LRC_CHECK0   = 7; %1st byte LRC check
        PACKET_LRC_CHECK1   = 8; %2nd byte LRC check
        PACKET_END          = 9; %trailer

        %data lenght for program's buffers
        MAX_BUFFER = 4096;
        
        % Command identifier, set in packet function
        REPLY_ACK             = 0;  %sensor answers with ack (successfull command)
        REPLY_NACK            = 1;  %sensor answers with Nack (command failed)
        GET_CONFIG            = 4;  %request actual config
        GET_STATUS            = 5;  %request actual status
        GOTO_COMMAND_MODE     = 6;  %set command mode
        GOTO_STREAM_MODE      = 7;  %set stream mode
        GET_SENSOR_DATA       = 9;  %data request        
        SET_TRANSMIT_DATA     = 10; %set data to transmit
        SET_STREAM_FREQ       = 11; %set freq of streaming mode
        GET_SERIAL_NUMBER     = 90; %request serial number, not implemented
        GET_DEVICE_NAME       = 91; %request sensor name
        GET_FIRMWARE_INFO     = 92; %request firmware info, not implemented
        
        %shift values to build the sent raw data to config transmit data
        %see enableTransmitData function
        SHIFT_SET_TRANSMIT_DATA = [9, 10, 11, 12, 13, 14, 16, 17, 18, 19, 21];
        DEFAULT_TRANSMIT_DATA =   [0,  0,  1,  1,  0,  0,  0,  1,  0,  0,  1];

        %Configuration register contents
        %definition of bit vectors to extract properly the info from an
        %answer to a getConfig command
        LPMS_GYR_AUTOCAL_ENABLED = bitshift(1, 30);
        LPMS_LPBUS_DATA_MODE_16BIT_ENABLED = bitshift(1, 22);
        LPMS_LINACC_OUTPUT_ENABLED = bitshift(1, 21);
        LPMS_DYNAMIC_COVAR_ENABLED = bitshift(1, 20);
        LPMS_GYR_CALIBRA_ENABLED = bitshift(1, 15);
        LPMS_ALTITUDE_OUTPUT_ENABLED = bitshift(1, 19);
        LPMS_QUAT_OUTPUT_ENABLED = bitshift(1, 18);
        LPMS_EULER_OUTPUT_ENABLED = bitshift(1, 17);
        LPMS_ANGULAR_VELOCITY_OUTPUT_ENABLED = bitshift(1, 16);
        LPMS_HEAVEMOTION_OUTPUT_ENABLED = bitshift(1, 14);
        LPMS_TEMPERATURE_OUTPUT_ENABLED = bitshift(1, 13);
        LPMS_GYR_RAW_OUTPUT_ENABLED = bitshift(1, 12);
        LPMS_ACC_RAW_OUTPUT_ENABLED = bitshift(1, 11);
        LPMS_MAG_RAW_OUTPUT_ENABLED = bitshift(1, 10);
        LPMS_PRESSURE_OUTPUT_ENABLED = bitshift(1, 9);

        %stream freq values read by getConfig
        LPMS_STREAM_FREQ_5HZ_ENABLED      = 0; 
        LPMS_STREAM_FREQ_10HZ_ENABLED     = 1;
        LPMS_STREAM_FREQ_30HZ_ENABLED     = 2;
        LPMS_STREAM_FREQ_50HZ_ENABLED     = 3;
        LPMS_STREAM_FREQ_100HZ_ENABLED    = 4;
        LPMS_STREAM_FREQ_200HZ_ENABLED    = 5;
        LPMS_STREAM_FREQ_300HZ_ENABLED    = 6;
        LPMS_STREAM_FREQ_500HZ_ENABLED    = 7;

        LPMS_STREAM_FREQ_MASK             = 7; %to extract stream freq from getConfig
        
        %set values
        LPMS_STREAM_FREQ_5HZ = 5;
        LPMS_STREAM_FREQ_10HZ = 10;
        LPMS_STREAM_FREQ_30HZ = 30;
        LPMS_STREAM_FREQ_50HZ = 50;
        LPMS_STREAM_FREQ_100HZ = 100;
        LPMS_STREAM_FREQ_200HZ = 200;
        LPMS_STREAM_FREQ_300HZ = 300;
        LPMS_STREAM_FREQ_500HZ = 500;
        FREQ = [5,...
                10,...
                30,...
                50,...
                100,...
                200,...
                300,...
                500];
        
        PARAMETER_SET_DELAY = 0.01; %wait step in wait loops
        DATA_QUEUE_SIZE = 64; %max data stored
    end
   
    properties
        
        BTconn; %object to manage BT communication
        isSensorConnected = false; %boolean for connection
        
        % define the properties of the class here, (like fields of a struct)
        rxBuffer = uint8(zeros(1, LpmsBT.MAX_BUFFER)); %buffer for received packets
        rawTxBuffer = uint8(zeros(1, LpmsBT.MAX_BUFFER)); %buffer for data to send
        inBytes = uint8(zeros(1, 2)); %buffer to aggregate 2 bytes for conversion into uint16
        rxState = LpmsBT.PACKET_END; %state of reading data process
        rxIndex = 0; %index in reading data process

        % extracted data during reading packet process
        currentAddress = 0;
        currentFunction = 0;
        currentLength = 0;
        lrcCheck = 0;

        waitForAck = false; %boolean for wait ack state
        waitForData = false; %boolean for wait data state
        ack = false; %true = ACK, false = NACK

        % Settings related
        imuId = 0;
        gyrRange = 0;
        accRange = 0;
        magRange = 0;
        streamingFrequency = 0;
        filterMode = 0;

        %boolean for actual sensor state: stream (true) or command (false)
        isStreamMode = true; 

        configurationRegister = 0; %buffer where transefer data for config parsing
%         configurationRegisterReady = false;
        sensorDataLength = 0; %lenght of sensor data: depends on enabled sensors
        serialNumber = 'none';
        serialNumberReady = false;
        deviceName = 'none';
        deviceNameReady = false;
        firmwareInfo= 'none';
        firmwareInfoReady = false;
        firmwareVersion = 'none';
        
        %enabled sensors booleans
        accEnable = false;
        gyrEnable = false;
        magEnable = false;
        angularVelEnable = false;
        quaternionEnable = false;
        eulerAngleEnable = false;
        linAccEnable = false;
        pressureEnable = false;
        altitudeEnable = false;
        temperatureEnable = false;
        heaveEnable = false;
        sixteenBitDataEnable = false;
        resetTimestampFlag = false;
        
        % sensorData struct where save data after parsing
        sensorData = struct(...
            'timestamp', 0.0, ...
            'gyr',  zeros(1,3), ...
            'acc',  zeros(1,3), ...
            'mag',  zeros(1,3), ...
            'angVel',  zeros(1,3), ...
            'quat',  zeros(1,4), ...
            'euler',  zeros(1,3), ...
            'linAcc',  zeros(1,3), ...
            'pressure', 0.0, ...
            'altitude', 0.0, ...
            'temperature', 0.0, ...
            'heave', 0.0 ...
        );
        
        %queue of struct sensorData, max lenght =  DATA_QUEUE_SIZE
        dataQueue = [];
    end

    methods 
        
        %% Connect to sensor, set command mode and retrieve actual config
        %is necessary to get actual config to set enabled sensor booleans
        function ret = connect(obj)
            disp("searching for devices...");
            BTlist = bluetoothlist; %list of available devices
            disp("search completed");
            index = find(contains(BTlist{:,"Name"},obj.DEV_NAME)==1, 1); %look for LPMSB2 device

            if(isempty(index)) %not found
                ret = false;
                disp("device not found");
                return;
            elseif(BTlist{index,"Channel"} == "Unknown") %found but unable to perform connection
                ret = false;
                disp("device not ready to connect");
                return;
            end
            
            disp("device: " + string(BTlist{index,"Name"}));
            try
                obj.BTconn = bluetooth(BTlist{index,"Name"}); %BT connection
            catch err
                disp(err);
            end

            %check if connection is successful
            if(~isempty(obj.BTconn))
                disp("connection successfull");
                obj.isSensorConnected = true;
            else
                disp("connection failed");
                obj.isSensorConnected = false;
                ret = obj.isSensorConnected;
                return;
            end

            %define packet terminator
            configureTerminator(obj.BTconn,"CR/LF");

            %force command mode
            try
                obj.sendData(obj.GOTO_COMMAND_MODE, 0); %send command without checking ack
                disp("command mode forced");
            catch err
                disp(err);
            end
            
            % Get sensor configuration
            try
                obj.setCommandMode(); %send command + wait for ack
                obj.getConfig(); %get sensor config + parsing
            catch e
                errordlg(e.message);
                disp(e);
                obj.disconnect(); % in case of error disconnects
            end

            ret = obj.isSensorConnected;

        end
        
        %% Disconnect from snesor and reset variables
        function ret = disconnect(obj)
            if(~obj.isSensorConnected)  %check connection
                ret = false;
                disp("no sensor connected");
                return;
            end
            
            delete(obj.BTconn); %terminate connection
            %reset variables
            obj.BTconn = [];
            obj.isSensorConnected = false;
            obj.isStreamMode = true;
            ret = true;
            disp("disconnected");

        end
        
        %% Set sensor to command mode
        function ret = setCommandMode(obj)
            %ret true if set is successful
            %false if error occures
            disp("setting command mode");
            if(~obj.isSensorConnected) %check connection
                disp("no sensor connected");
                ret = false;
                return;
            end          
            
            obj.configCallback(11); % set interrupt
            obj.waitForAck = true;
            obj.sendData(obj.GOTO_COMMAND_MODE, 0); %send command
            if ~obj.waitForAckLoop() %wait loop
                % timeout, manual read bytes avaiable
                disp('setCommandMode wait for ack timeout');
                obj.readCallbackFcn(obj.BTconn); %force data read
            end

            if(obj.ack) %received ACK
                obj.isStreamMode = false; %now in command mode
                obj.configCallback("off"); %disable interrupt function
                ret = true;
            else %received NACK
                disp("setCommandMode failed");
                ret = false;
            end

            obj.ack = false; %reset variable    

        end
        
        %% Set sensor to streaming mode
        function ret = setStreamingMode(obj)
            %ret true if set is successful
            %false if error occures
            disp("setting streaming mode");
            if(~obj.isSensorConnected) %check connection
                disp("no sensor connected");
                ret = false;
                return;
            end

            obj.configCallback(11); % set interrupt
            obj.waitForAck = true;
            obj.sendData(obj.GOTO_STREAM_MODE, 0); %send command
            if ~obj.waitForAckLoop() %wait loop
                % timeout, manual read bytes avaiable
                disp('setStreamingMode wait for ack timeout');
                obj.readCallbackFcn(obj.BTconn); %force data read
            end

            if(obj.ack) %received ACK
                obj.configCallback("off"); %disable interrupt function
                obj.isStreamMode = true; %now in streaming mode
                obj.configCallback(11+obj.sensorDataLength); % set interrupt
                ret = true;
            else %received NACK
                disp("setStreamingMode failed");
                ret = false;
            end
            obj.ack = false;

        end
        
        %% Request sensor actual config
        function ret = getConfig(obj)
            %return false if no connected
            disp("getting config");
            if(~obj.isSensorConnected) %check connection
                ret = false;
                disp("no sensor connected");
                return;
            end
            
            obj.configCallback(11); % set interrupt
            obj.waitForData = true;
            obj.sendData(obj.GET_CONFIG, 0);  %send command
            if ~obj.waitForDataLoop() %wait loop
                % timeout, manual read bytes avaiable
                disp('getConfig wait for data timeout');
                obj.readCallbackFcn(obj.BTconn); %force data read
            end

            if(~obj.isStreamMode) %if not in stream mode
                obj.configCallback("off"); %disable interrupt
            else    
                obj.configCallback(11+obj.sensorDataLength); % set interrupt
            end
            
        end
        
        %% Dispaly actaul config to terminal
        function dispConfig(obj) %display sensor config
            if(~obj.isSensorConnected)
                disp("no sensor connected");
                return;
            end

            disp("streamingFrequency: "+ string(obj.streamingFrequency));
            if obj.sixteenBitDataEnable
                disp("dataMode: 16bit");
            else
                disp("dataMode: 32bit");
            end

            strData = "Enabled data: ";
            if(obj.gyrEnable) 
                strData = strcat(strData, "raw gyro");
            end
            if(obj.accEnable) 
                strData = strcat(strData, "; raw acc");
            end
            if(obj.magEnable) 
                strData = strcat(strData, "; raw mag");
            end
            if(obj.angularVelEnable) 
                strData = strcat(strData, "; angular vel");
            end
            if(obj.quaternionEnable) 
                strData = strcat(strData, "; quaternion");
            end
            if(obj.eulerAngleEnable) 
                strData = strcat(strData, "; Euler angles");
            end
            if(obj.linAccEnable) 
                strData = strcat(strData, "; linear acc");
            end
            if(obj.pressureEnable) 
                strData = strcat(strData, "; pressure");
            end
            if(obj.temperatureEnable) 
                strData = strcat(strData, "; temperature");
            end
            if(obj.altitudeEnable) 
                strData = strcat(strData, "; altitude");
            end
            if(obj.heaveEnable) 
                strData = strcat(strData, "; heave motion");
            end
            disp(strData);
            
        end
        
        %% Set wich data the sensor will transmit
        %boolvector: defines wich values will be transmit following the
        %order listed below
        function ret = setTransmitData(obj,boolVector)
            %ret true if set is successful
            %false if error occures

            disp("setting transmit data");
            %ret false if sensor not connected

%             boolVector values order:
%             [ press, mag, acc, gyro, temp, heave, angVel, euler, quat,
%             alti, linAcc]
            
            if(~obj.isSensorConnected) %check connection
                ret = false;
                disp("no sensor connected");
                return;
            end
                            
            %build data to send
            if(isempty(boolVector)) %if no param is passed
                boolVector = obj.DEFAULT_TRANSMIT_DATA; %use default
            end
            %for efficiency and to avoid errors choose the shortest one
            len = min(length(boolVector),length(obj.SHIFT_SET_TRANSMIT_DATA)); 
            commandData = uint32(0); %data to send is a 4 bytes value
            for i=1:len
                if(boolVector(i)) %add boolean bits to the data packet
                                               %shift a bit=1 in the right position and add it to packet                                               
                    commandData = commandData + bitshift(1,obj.SHIFT_SET_TRANSMIT_DATA(i));
                end
            end
            obj.rawTxBuffer(1:4) = typecast(commandData, 'uint8'); %cast the packet in 4 bytes data vector
            
            obj.configCallback(11);  % set interrupt
            obj.waitForAck = true;
            obj.sendData(obj.SET_TRANSMIT_DATA, 4); %send command
            if ~obj.waitForAckLoop() % wait loop
                % timeout, manual read bytes avaiable
                disp('setEnabledData wait for ack timeout');
                obj.readCallbackFcn(obj.BTconn); %force data read
            end
            
            if(obj.ack) %received ACK
                if(~obj.isStreamMode) %if not in stream mode
                    obj.configCallback("off"); %disable interrupt
                else    
                    obj.configCallback(11+obj.sensorDataLength); % set interrupt
                end
                ret = true;
                % update the config
                disp("setEnabledData successful, new config:");
                obj.getConfig();
            else %received NACK
                disp("setEnabledData failed");
                ret = false;
            end
            obj.ack = false;
        end
        
        %% Set streaming frequency of the sensor
        function ret = setStreamFreq(obj,freq)
            %ret true if set is successful
            %false if error occures

            disp("setting streaming freq");

            if(~obj.isSensorConnected) %check connection
                ret = false;
                disp("no sensor connected");
                return;
            end
            
            %check if input param is an acceptable value
            if(isempty(find(obj.FREQ==freq))) %#ok<EFIND> 
                disp("given freq not valid: "+string(freq));
                ret = false;
                return;
            end

            commandData = uint32(freq);  %data to send is a 4 bytes value
            obj.rawTxBuffer(1:4) = typecast(commandData, 'uint8'); %cast the packet in 4 bytes data vector
            obj.configCallback(11);  % set interrupt
            obj.waitForAck = true;
            obj.sendData(obj.SET_STREAM_FREQ, 4); %send command
            if ~obj.waitForAckLoop() % wait loop
                % timeout, manual read bytes avaiable
                disp('setStreamFreq wait for ack timeout');
                obj.readCallbackFcn(obj.BTconn); %force data read
            end
            
            if(obj.ack) %received ACK
                if(~obj.isStreamMode) %if not in stream mode
                    obj.configCallback("off"); %disable interrupt
                else 
                    obj.configCallback(11+obj.sensorDataLength); % set interrupt
                end
                ret = true;
                disp("setStreamFreq successful");
                % update streaming freq
                obj.streamingFrequency = freq;
            else %received NACK
                disp("setStreamFreq failed");
                ret = false;
            end
            obj.ack = false;

        end
        
        %% Get newest data from sensor
        function ret = getCurrentSensorData(obj)
            %ret data if successful
            %empty if fail

            if(~obj.isSensorConnected) %check connection
                ret = [];
                disp("no sensor connected");
                return;
            end
            
            if (obj.isStreamMode) %if stream mode
                % retrieve newest data from sensor: last values inserted in
                % the data struct
                ret = obj.sensorData;  
            else
                obj.configCallback(11 + obj.sensorDataLength); % set interrupt
                obj.waitForData = true;
                obj.sendData(obj.GET_SENSOR_DATA,0); % request to send data
                obj.waitForDataLoop();
                ret = obj.sensorData;
                obj.configCallback("off"); %disable interrupt
            end
        end
        
        %% Get oldest data from sensor
        function ret = getQueueSensorData(obj)
            %ret data if successful
            %empty if fail

            if(~obj.isSensorConnected) %check connection
                ret = false;
                disp("no sensor connected");
                return;
            end

            
            if ~isempty(obj.dataQueue)
                ret = obj.dataQueue(1); % Retrieve oldest data in data queue
                obj.dataQueue = obj.dataQueue(2:end); %shift the vector
            else
                ret = [];
            end
        end

    end

    methods (Access = private)
         
        function readCallbackFcn(obj, hObject, eventdata) %method called by the interrupt
            if(obj.isSensorConnected) %check connection
                try
                    n = hObject.NumBytesAvailable; %bytes available for reading
                    if n > 0 
                        data = read(hObject,n,"char"); %read data
                        obj.parse(data, n); %parse data
                    end
                catch err
                    disp(err);
                    disp("error occured during reading");
                end
            else
                disp("sensor not connected");
            end
        end

        function ret = waitForAckLoop(obj)
            %ret true if successfully receivs ack
            %false if fail

            timeout = 0;
            while (obj.waitForAck && timeout < 100) %until timout or ack
                pause(obj.PARAMETER_SET_DELAY); %wait
                timeout = timeout + 1;
            end
            if timeout >= 100 %if timeout reached
                ret = false;
            else
                ret = true;
            end
        end
        
        function ret = waitForDataLoop(obj)
            %ret true if successfully received data
            %false if fail

            timeout = 0;
            while (obj.waitForData && timeout < 100) %until timout or data read
                pause(obj.PARAMETER_SET_DELAY); %wait
                timeout = timeout + 1; %until timout ot ack
            end
            if timeout >= 100 %if timeout reached
                ret = false;
            else
                ret = true;
            end
        end

        function ret = sendData(obj, command, length) %lenght as number of bytes
            %ret true if successfully sends data
            %    false + close connection if fail

            %build packet
            txBuffer = zeros(1, 11+length, "uint8");
            txBuffer(1) = 0x3A; %header
            txBuffer(2:3) = typecast(uint16(obj.imuId), 'uint8'); %imu ID
            txBuffer(4:5) = typecast(uint16(command), 'uint8'); %command code
            txBuffer(6:7) = typecast(uint16(length), 'uint8'); %data lenght
            txLrcCheck = 0;
            for i=2:7
                txLrcCheck = txLrcCheck + txBuffer(i); %update LRC
            end
            for i = 1:length
                txBuffer(7+i) = obj.rawTxBuffer(i); %add data byte
                txLrcCheck = txLrcCheck + obj.rawTxBuffer(i); %update LRC
            end
            txBuffer(8+length:9+length) = typecast(uint16(txLrcCheck), 'uint8'); %LRC
            txBuffer(10+length)=0x0D; %terminator
            txBuffer(11+length)=0x0A; %terminator
            
            try
                write(obj.BTconn, txBuffer, "uint8"); %send data
                ret = true;
            catch
                ret = false;
                obj.disconnect()
                disp("failed to send command, interrupting connection");
            end
        end

        function obj = parse(obj, buf, nBytes)
            for i=1:nBytes
                d = buf(i); %actual byte
                switch obj.rxState 
                    case obj.PACKET_END %default state (header)
                        if (d == 0x3A) %check header
                            obj.rxState = obj.PACKET_ADDRESS0; %switch to address first byte
                        end

                    case obj.PACKET_ADDRESS0 %address first byte
                       obj.inBytes(1) = d; %saves first byte in buffer
                       obj.rxState = obj.PACKET_ADDRESS1; %switch to address second byte

                    case obj.PACKET_ADDRESS1  %address second byte
                        obj.inBytes(2) = d; %saves second byte in buffer
                        obj.currentAddress = typecast(obj.inBytes,'uint16'); %converts 2 bytes in address
                        obj.imuId = obj.currentAddress; %save address
                        obj.rxState = obj.PACKET_FUNCTION0; %switch to command ID first byte

                    case obj.PACKET_FUNCTION0 %command ID first byte
                        obj.inBytes(1) = d; %saves command ID first byte in buffer
                        obj.rxState = obj.PACKET_FUNCTION1; %switch to command ID second byte

                    case obj.PACKET_FUNCTION1 %command ID second byte
                        obj.inBytes(2) = d; %saves command ID second byte in buffer
                        obj.currentFunction = typecast(obj.inBytes,'uint16'); %converts 2 bytes in command ID
                        obj.rxState = obj.PACKET_LENGTH0; %switch to data lenght first byte

                    case obj.PACKET_LENGTH0 %data lenght first byte
                        obj.inBytes(1) = d; %saves data lenght first byte in buffer
                        obj.rxState = obj.PACKET_LENGTH1; %switch to data lenght second byte

                    case obj.PACKET_LENGTH1 %data lenght second byte
                        obj.inBytes(2) = d; %saves data lenght second byte in buffer
                        obj.currentLength = typecast(obj.inBytes,'uint16'); %converts 2 bytes in data lenght
                        obj.rxIndex = 0; %set index to read next bytes (data field)
                        obj.rxState = obj.PACKET_RAW_DATA; %switch to read data
                        obj.lrcCheck = obj.currentAddress + obj.currentFunction + obj.currentLength; %update LRC
                      
                    case obj.PACKET_RAW_DATA %data read
                        if obj.rxIndex == obj.currentLength %finish read
                            obj.inBytes(1) = d; %saves LRC first byte in buffer
                            obj.rxState = obj.PACKET_LRC_CHECK1; %switch to LRC first byte
                        else
                            if (obj.rxIndex < obj.MAX_BUFFER) %reading
                                obj.rxBuffer(obj.rxIndex+1) = d; %saves byte in buffer
                                obj.rxIndex = obj.rxIndex + 1; %increment index
                                obj.lrcCheck = obj.lrcCheck + d; %update LRC
                            else
                                obj.rxState = obj.PACKET_END; %error
                            end
                        end

                    case obj.PACKET_LRC_CHECK1 %LRC first byte
                        obj.inBytes(2) = d; %saves LRC second byte in buffer
                        lrcReceived = typecast(obj.inBytes,'uint16'); %converts 2 bytes in LRC
                        if (lrcReceived == obj.lrcCheck) %check LRC
                            obj.parseFunction(); %parse data
                        else
                            disp("error in parsing: LRC doesn't match"); %LRC error
                        end
                        obj.rxState = obj.PACKET_END; %end
                      
                    otherwise 
                        obj.rxState = obj.PACKET_END;                   
                end
            end
        end
        
        %% Depending on thr function of the packet receive, execute the associated instructions
        function parseFunction(obj)
            switch (obj.currentFunction) %depending on the command ID read:
                case obj.REPLY_ACK %set function successful
                    disp('REPLY_ACK') 
                    obj.waitForAck = false; %stop waiting for ack
                    obj.ack = true; %ack is positive
                    return;
                    
                case obj.REPLY_NACK %set function failed
                    disp('REPLY_NACK') 
                    obj.waitForAck = false; %stop waiting for ack
                    obj.ack = false; %ack is negative
                    return;
            
                case obj.GET_CONFIG %response to setConfig
                    disp('GET_CONFIG') 
                    obj.configurationRegister = obj.convertRxbytesToInt(0, obj.rxBuffer); %cast to int
                    obj.parseConfig(obj.configurationRegister); %parse config data
                    obj.waitForData = false; %stop waiting for data
                    return;
                    
                case obj.GET_SENSOR_DATA %sensor data packet
                    disp('GET_SENSOR_DATA')
                    obj.parseSensorData(); %parse sensor data
                    obj.waitForData = false; %stop waiting for data
                    return;
                    
                case obj.GET_DEVICE_NAME %name data packet
%                     disp('GET_DEVICE_NAME')
                    obj.deviceName = obj.convertRxbytesToString(16, obj.rxBuffer); %cast to string
                    obj.deviceNameReady = true; %name is available
                    obj.waitForData = false; %stop waiting for data
                    return;
            end
        end
        
        function ret = convertRxbytesToInt(obj, offset, buf)
             ret = typecast(buf(1+offset:4+offset),'uint32'); %cast to int
        end

        function ret = convertRxbytesToFloat(obj, offset, buf)
             ret = typecast(buf(1+offset:4+offset),'single'); %cast to float
        end

        function ret = convertRxbytesToString(obj, offset, buf) %cast to string
             buf(1:offset)
             ret = char(buf(1:offset));
        end
        
        %% Parse raw config data received after a getConfig
        %compute total data lenght according to how many sensors are
        %enabled
        function ret = parseConfig(obj, config)

            %stream freq
            freqSettings = bitand(config, obj.LPMS_STREAM_FREQ_MASK); %extract info
            switch(freqSettings) %set variable
                case obj.LPMS_STREAM_FREQ_5HZ_ENABLED
                    obj.streamingFrequency = obj.LPMS_STREAM_FREQ_5HZ;
                case obj.LPMS_STREAM_FREQ_10HZ_ENABLED
                    obj.streamingFrequency = obj.LPMS_STREAM_FREQ_10HZ;
                case obj.LPMS_STREAM_FREQ_30HZ_ENABLED
                    obj.streamingFrequency = obj.LPMS_STREAM_FREQ_30HZ;
                case obj.LPMS_STREAM_FREQ_50HZ_ENABLED
                    obj.streamingFrequency = obj.LPMS_STREAM_FREQ_50HZ;
                case obj.LPMS_STREAM_FREQ_100HZ_ENABLED
                    obj.streamingFrequency = obj.LPMS_STREAM_FREQ_100HZ;
                case obj.LPMS_STREAM_FREQ_200HZ_ENABLED
                    obj.streamingFrequency = obj.LPMS_STREAM_FREQ_200HZ;
                case obj.LPMS_STREAM_FREQ_300HZ_ENABLED
                    obj.streamingFrequency = obj.LPMS_STREAM_FREQ_300HZ;
                case obj.LPMS_STREAM_FREQ_500HZ_ENABLED
                    obj.streamingFrequency = obj.LPMS_STREAM_FREQ_500HZ;
                otherwise
                    disp("Error during readign stream freq");
                    ret = false;
            end
            disp("streamingFrequency: "+ string(obj.streamingFrequency));
            
            %16bit mode
            if bitand(config, obj.LPMS_LPBUS_DATA_MODE_16BIT_ENABLED)%extract info
                obj.sixteenBitDataEnable = true;
            else
                obj.sixteenBitDataEnable = false;
            end
            if obj.sixteenBitDataEnable
                disp("dataMode: 16bit");
            else
                disp("dataMode: 32bit");
            end
            
            %gyroscope raw

            obj.sensorDataLength=0; %tot data lenght
            if bitand(config, obj.LPMS_GYR_RAW_OUTPUT_ENABLED)%extract info
                obj.gyrEnable = true;
                % increment tot data lenght
                if (obj.sixteenBitDataEnable)%2 bytes (16bit mode) per axis = 6
                   obj.sensorDataLength = obj.sensorDataLength + 6;
                else %4 bytes (32bit mode) per axis = 12
                   obj.sensorDataLength = obj.sensorDataLength + 12;
                end
            else
                obj.gyrEnable = false;
            end
            disp("gyrEnable: "+ string(obj.gyrEnable));
            
            %accelerometer raw
            if bitand(config, obj.LPMS_ACC_RAW_OUTPUT_ENABLED) %extract info
                obj.accEnable = true;
                % increment tot data lenght
                if (obj.sixteenBitDataEnable)%2 bytes (16bit mode) per axis = 6
                   obj.sensorDataLength = obj.sensorDataLength + 6;
                else %4 bytes (32bit mode) per axis = 12
                   obj.sensorDataLength = obj.sensorDataLength + 12;
                end
            else
                obj.accEnable = false;
            end
            disp("accEnable: " + string(obj.accEnable));

            %magnetometer raw
            if bitand(config, obj.LPMS_MAG_RAW_OUTPUT_ENABLED) %extract info
                obj.magEnable = true;
                % increment tot data lenght
                if (obj.sixteenBitDataEnable)%2 bytes (16bit mode) per axis = 6
                    obj.sensorDataLength = obj.sensorDataLength + 6;
                else %4 bytes (32bit mode) per axis = 12
                    obj.sensorDataLength = obj.sensorDataLength + 12;
                end
            else
                obj.magEnable = false;
            end
            disp("magEnable: " + string(obj.magEnable));
            
            %angular velocity
            if bitand(config, obj.LPMS_ANGULAR_VELOCITY_OUTPUT_ENABLED) %extract info
                obj.angularVelEnable = true;
                % increment tot data lenght
                if (obj.sixteenBitDataEnable)%2 bytes (16bit mode) per axis = 6
                    obj.sensorDataLength = obj.sensorDataLength + 6;
                else %4 bytes (32bit mode) per axis = 12
                    obj.sensorDataLength = obj.sensorDataLength + 12;
                end
            else
                obj.angularVelEnable = false;
            end
            disp("angularVelEnable: " + string(obj.angularVelEnable));
            
            %quaternions
            if bitand(config, obj.LPMS_QUAT_OUTPUT_ENABLED) %extract info
                obj.quaternionEnable = true;
                % increment tot data lenght
                if (obj.sixteenBitDataEnable)%2 bytes (16bit mode) per value = 8
                    obj.sensorDataLength = obj.sensorDataLength + 8;
                else %4 bytes (32bit mode) per value = 16
                    obj.sensorDataLength = obj.sensorDataLength + 16;
                end
            else
                obj.quaternionEnable = false;
            end
            disp("quaternionEnable: " + string(obj.quaternionEnable));
            
            %euler angles
            if bitand(config, obj.LPMS_EULER_OUTPUT_ENABLED) %extract info
                obj.eulerAngleEnable = true;
                % increment tot data lenght
                if (obj.sixteenBitDataEnable)%2 bytes (16bit mode) per axis = 6
                    obj.sensorDataLength = obj.sensorDataLength + 6;
                else %4 bytes (32bit mode) per axis = 12
                    obj.sensorDataLength = obj.sensorDataLength + 12;
                end
            else
                obj.eulerAngleEnable = false;
            end
            disp("eulerAngleEnable: " + string(obj.eulerAngleEnable));
            
            %linear acceleration
            if bitand(config, obj.LPMS_LINACC_OUTPUT_ENABLED) %extract info
                obj.linAccEnable = true;
                % increment tot data lenght
                if (obj.sixteenBitDataEnable)%2 bytes (16bit mode) per axis = 6
                    obj.sensorDataLength = obj.sensorDataLength + 6;
                else %4 bytes (32bit mode) per axis = 12
                    obj.sensorDataLength = obj.sensorDataLength + 12;
                end
            else
                obj.linAccEnable = false;
            end
            disp("linAccEnable: " + string(obj.linAccEnable));
            
            %pressure
            if bitand(config, obj.LPMS_PRESSURE_OUTPUT_ENABLED) %extract info
                obj.pressureEnable = true;
                % increment tot data lenght
                if (obj.sixteenBitDataEnable)%2 bytes (16bit mode)
                    obj.sensorDataLength = obj.sensorDataLength + 2;
                else %4 bytes (32bit mode)
                    obj.sensorDataLength = obj.sensorDataLength + 4;
                end
            else
                obj.pressureEnable = false;
            end
            disp("pressureEnable: " + string(obj.pressureEnable));
            
            %temperature
            if bitand(config, obj.LPMS_TEMPERATURE_OUTPUT_ENABLED) %extract info
                obj.temperatureEnable = true;
                % increment tot data lenght
                if (obj.sixteenBitDataEnable)%2 bytes (16bit mode)
                    obj.sensorDataLength = obj.sensorDataLength + 2;
                else %4 bytes (32bit mode)
                    obj.sensorDataLength = obj.sensorDataLength + 4;
                end
            else
                obj.temperatureEnable = false;
            end
            disp("temperatureEnable: " + string(obj.temperatureEnable));
            
            %altitude
            if bitand(config, obj.LPMS_ALTITUDE_OUTPUT_ENABLED) %extract info
                obj.altitudeEnable = true;
                % increment tot data lenght
                if (obj.sixteenBitDataEnable)%2 bytes (16bit mode)
                    obj.sensorDataLength = obj.sensorDataLength + 2;
                else %4 bytes (32bit mode)
                    obj.sensorDataLength = obj.sensorDataLength + 4;
                end
            else
                obj.altitudeEnable = false;
            end
            disp("altitudeEnable: " + string(obj.altitudeEnable));
            
            %heave motion
            if bitand(config, obj.LPMS_HEAVEMOTION_OUTPUT_ENABLED) %extract info
                obj.heaveEnable = true;
                % increment tot data lenght
                if (obj.sixteenBitDataEnable)%2 bytes (16bit mode)
                    obj.sensorDataLength = obj.sensorDataLength + 2;
                else %4 bytes (32bit mode)
                    obj.sensorDataLength = obj.sensorDataLength + 4;
                end
            else
                obj.heaveEnable = false;
            end
            disp("heaveEnable: " + string(obj.heaveEnable));
                         
        end
        
        %% Parse raw data from a sensor data packet
        function parseSensorData(obj)
            % TODO: Implement 16bit data parsing
            r2d = 57.2958; %radiant to degrees
            obj.sensorData.timestamp = double(obj.convertRxbytesToInt(0, obj.rxBuffer))*0.0025; %first 4 bytes: timestamp
            if (~obj.sixteenBitDataEnable)
                d = typecast(obj.rxBuffer(5:obj.sensorDataLength+4), 'single'); %converts remaining data in float
                o = 1; %index for read data

                %check booleans and read enabled data
                if obj.gyrEnable
                    for i=1:3 
                        obj.sensorData.gyr(i) = d(o) * r2d;
                        o = o+1;
                    end
                end
                
                if obj.accEnable
                    for i=1:3
                        obj.sensorData.acc(i) = d(o);
                        o = o+1;
                    end
                end
                
                if obj.magEnable
                    for i=1:3
                        obj.sensorData.mag(i) = d(o);
                        o = o+1;
                    end
                end
                
                if obj.angularVelEnable
                    for i=1:3
                       obj.sensorData.angVel(i) = d(o)* r2d;
                       o = o+1;
                    end
                end
                
                if obj.quaternionEnable
                    for i=1:4
                       obj.sensorData.quat(i) = d(o);
                       o = o+1;
                    end
                end
                
                if obj.eulerAngleEnable
                    for i=1:3
                       obj.sensorData.euler(i) = d(o)* r2d;
                       o = o+1;
                    end
                end
                
                if obj.linAccEnable
                    for i=1:3
                       obj.sensorData.linAcc(i) = d(o);
                       o = o+1;
                    end
                end
                
                if obj.pressureEnable
                    obj.sensorData.pressure = d(o);
                    o = o+1;
                end
                
                if obj.altitudeEnable
                    obj.sensorData.altitude = d(o);
                    o = o+1;
                end
                
                if obj.temperatureEnable
                    obj.sensorData.temperature = d(o);
                    o = o+1;
                end
                
                if obj.heaveEnable
                    obj.sensorData.heave = d(o);
                end
                
            end
             
             % add data to queue
             if length(obj.dataQueue) == obj.DATA_QUEUE_SIZE %full
                 obj.dataQueue = obj.dataQueue(2:end); %shift
             end
             obj.dataQueue = [obj.dataQueue obj.sensorData]; %push back in queue
             
             
        end
    
        function configCallback(obj, n) %config interrupt
            if(strcmp(string(n),"off")) %disable
%                 disp("trigger off");
                configureCallback(  obj.BTconn, ...
                                    "off"...
                                 );
            elseif(strcmp(string(n),"terminator")) %use terminator
%                 disp("set terminator trigger");
                configureCallback(  obj.BTconn, ...
                                    "terminator", ...
                                    @obj.readCallbackFcn ...
                                 );
            elseif(n>0)
%                 disp("set n bytes trigger: "+string(n)); %use lenght
                configureCallback(  obj.BTconn, ...
                                    "byte", ...
                                    n, ...
                                    @obj.readCallbackFcn ...
                                 );
            else
                disp("argument not valid"); %error-> disable
                configureCallback(  obj.BTconn, ...
                                    "off"...
                                 );
            end

        end

     end

end