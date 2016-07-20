function runTriplePortExperiment(varargin)

global arduinoConnection arduinoPort
global arduinoMessageString

global p % parameter structure
global info % structure containing mouse name and folder to be saved in
%% Setup

% cleanup routine to be executed even if this function is terminated early
finishup = onCleanup(@triplePortCleanup);

% seed random number generator (to prevent repeating the same values on
% different experiments)
rng('shuffle');

%gets the mouse's name
mouseName = info.mouseName;
%creates the log file name
mouseLog = strcat(mouseName,'_log');
%sets up the logging for mouseLog
setupLogging(mouseLog);


% log all paramters and inital values
fn = fieldnames(p);
for i=1:length(fn)
    fName = fn{i};
    logValue(fName,p.(fName));
end
rngState = rng;
logValue('RNG Seed', rngState.Seed);
logValue('RNG Type', rngState.Type);


% set up Arduino
arduinoMessageString = '';
clearPorts();
arduinoPortNum = findArduinoPort();
if ~arduinoPortNum
    disp('Can''t find serial port with Arduino')
    return
end
arduinoConnection = 0;
arduinoPort = setupArduinoSerialPort(arduinoPortNum);
% wait for Arduino startup
fprintf('Waiting for Arduino startup')
while (arduinoConnection == 0)
    fprintf('.');
    pause(0.5);
end
fprintf('\n')



%% setup ports/arduino
global centerPort rightPort leftPort

centerPort = NosePort(7,13);
centerPort.setLEDPin(4);
centerPort.deactivate();
centerPort.noseInFunc = @centerPortPokeFunc;
logValue('center port ID', centerPort.portID);

rightPort = NosePort(8,3);
rightPort.setLEDPin(9);
rightPort.setRewardDuration(p.rewardDurationRight);
rightPort.setToSingleRewardMode();
rightPort.rewardFunc = @rewardFunc;
rightPort.noseOutFunc = @endTrial;
rightPort.noseInFunc = @noseIn;
logValue('right port ID', rightPort.portID);

leftPort = NosePort(6,3);
leftPort.setLEDPin(10);
leftPort.setRewardDuration(p.rewardDurationLeft);
leftPort.setToSingleRewardMode();
leftPort.rewardFunc = @rewardFunc;
leftPort.noseOutFunc = @endTrial;
leftPort.noseInFunc = @noseIn;
logValue('left port ID', leftPort.portID);


if p.centerPokeTrigger
    rightPort.deactivate();
    leftPort.deactivate();
else
    rightPort.activate();
    leftPort.activate();
end


%% run trials
global numBlocks
numBlocks = struct;
numBlocks.left = 0;
numBlocks.right = 0;
if p.rightRewardProb >= p.leftRewardProb
    numBlocks.right = 1;
else
    numBlocks.left = 1;
end

global currBlockReward blockRange currBlockSize
currBlockReward = 0;
blockRange = [p.blockRangeMin:p.blockRangeMax];
currBlockSize = randi([min(blockRange),max(blockRange)]);
display(currBlockSize)

global pokeHistory pokeCount
pokeCount = 0;
pokeHistory= struct;

global iti lastPokeTime
iti = p.minInterTrialInterval;
lastPokeTime = datevec(now);

%create stats structure for online analysis and visualization
global stats
% initialize the first entry of stats to be zeros
stats = initializestats;
cumstats = cumsumstats(stats);
%create figure for onilne visualization
global h
h = initializestatsfig(cumstats);


%% run the program.....
%runs as long as info.running has not been set to false via the Stop
%Experiment button
while info.running
    pause(0.1)
        % actively probe whether or note enough time has elapsed to start a
    % new trial. If so, turn on the LED>
    if etime(datevec(now),lastPokeTime) >= iti
        centerPort.ledOn();
    end
end
end

%% Subfunctions


%% Nose In Functions
function noseIn(portID)
disp('noseIn')
global p
global pokeHistory pokeCount lastPokeTime 
global rightPort leftPort centerPort
global activateLeft activateRight
global stats
global iti
global h

pokeCount = pokeCount+1; %increment pokeCount
timeSinceLastPoke = etime(datevec(now),lastPokeTime);

%Update pokeHistory
pokeHistory(pokeCount).timeStamp = now;
if portID == rightPort.portID
    pokeHistory(pokeCount).portPoked = 'rightPort';
elseif portID == leftPort.portID
    pokeHistory(pokeCount).portPoked = 'leftPort';
elseif portID == centerPort.portID
    pokeHistory(pokeCount).portPoked = 'centerPort';
end

%first need to deal with special case of first poke
if pokeCount == 1
    if portID == centerPort.portID
        pokeHistory(pokeCount).isTRIAL = 1;
    else
        pokeHistory(pokeCount).isTRIAL = 0;
    end
%if this is a left or right port, there is a possibility this is the
%decision poke of a trial. If so, there's a bunch of info we need.
elseif portID == rightPort.portID || portID == leftPort.portID
    %check to see if we are in a trial.
    if pokeHistory(pokeCount-1).isTRIAL == 1
        %if we are in a trial, check to see if we are within the
        %response time (p.centerPokeRewardWindow). If so, set
        %pokeHistory.isTrial to 2 (which denotes that this is a
        %decision poke), and set the pokeHistory.trialTime as the time
        %elapsed from the trial iniation (last poke) to now.
        if timeSinceLastPoke <= p.centerPokeRewardWindow
            pokeHistory(pokeCount).isTRIAL = 2;
            pokeHistory(pokeCount).trialTime = etime(datevec(now),lastPokeTime);
            pokeHistory(pokeCount).leftPortStats.prob = p.leftRewardProb;
            pokeHistory(pokeCount).rightPortStats.prob = p.rightRewardProb;
            pokeHistory(pokeCount).leftPortStats.ACTIVATE = activateLeft;
            pokeHistory(pokeCount).rightPortStats.ACTIVATE = activateRight;
            %if a decision is made, turn off the LEDs.
            rightPort.ledOff();
            leftPort.ledOff();
        else %if reward window is passed, than this is not a trial poke
            pokeHistory(pokeCount).isTRIAL = 0;
        end
    else %if we're not in a trial then any left or right poke is an error poke.
        pokeHistory(pokeCount).isTRIAL = 0;
        %and we should turn off the lights until the center port is active
        %again
        centerPort.ledOff();
    end
    %finally have to deal with the center pokes
elseif portID == centerPort.portID
    if pokeHistory(pokeCount-1).isTRIAL == 0 || pokeHistory(pokeCount-1).isTRIAL == 2
        if timeSinceLastPoke >= iti
            pokeHistory(pokeCount).isTRIAL = 1;
        else
            pokeHistory(pokeCount).isTRIAL = 0;
        end
    elseif pokeHistory(pokeCount-1).isTRIAL == 1
        if timeSinceLastPoke < p.centerPokeRewardWindow
            pokeHistory(pokeCount).isTRIAL = 0;
            deactivateSidePorts(); % this type of poke is technically a
            %decision poke in the center, so we should deactivate the
            %ports. I added this line 4/21/16. Before this, two quick pokes
            %in the center followed by a poke on the side could lead to a
            %reward.
            %should also turn off the side LEDs
            rightPort.ledOff();
            leftPort.ledOff();
        elseif timeSinceLastPoke >= iti
            pokeHistory(pokeCount).isTRIAL = 1;
        else
            pokeHistory(pokeCount).isTRIAL = 0;
        end
    end
end
%in order to run update stats, we need a value for pokeHistory.REWARD
pokeHistory(pokeCount).REWARD = 0;

%update stats and refresh figures
stats = updatestats(stats,pokeHistory(pokeCount),pokeCount);
global handlesCopy
leftRewards = sum(stats.rewards.left);
rightRewards = sum(stats.rewards.right);
totalRewards = leftRewards + rightRewards;
leftTrials = sum(stats.trials.left)/2;
rightTrials = sum(stats.trials.right)/2;
totalTrials = leftTrials + rightTrials;
global numBlocks
leftBlocks = numBlocks.left;
rightBlocks = numBlocks.right;
totalBlocks = leftBlocks+rightBlocks;
data = [leftRewards, rightRewards, totalRewards; leftTrials, rightTrials, ...
    totalTrials;leftBlocks,rightBlocks,totalBlocks];
set(handlesCopy.statsTable,'data',data);
cumstats = cumsumstats(stats);
updatestatsfig(cumstats,h,pokeCount);

%update the lastPokeTime
lastPokeTime = datevec(now);

end


function centerPortPokeFunc(portID)
disp('centerPortPokeFunc')
noseIn(portID);

global p pokeHistory pokeCount
global activateLeft activateRight
global centerPort rightPort leftPort

if p.centerPokeTrigger % if we're in centerPokeTrigger mode
    %see if we are currently in a trial
    %Note   isTRIAL == 1 means that centerPort has correctly initiated trial
           %isTRIAL == 0 means that the poke is 'incorrect' and not a trial
           %isTRIAL == 2 means that the poke is a decision poke           
    if pokeHistory(pokeCount).isTRIAL == 1;
        centerPort.ledOff();
        leftPort.ledOn();
        rightPort.ledOn();
        executeFunctionWithDelay(@rightPort.ledOff,p.centerPokeRewardWindow);
        executeFunctionWithDelay(@leftPort.ledOff,p.centerPokeRewardWindow);
        %activate side ports with appropriate probs
        activateLeft = (rand <= p.leftRewardProb); % activate left port with prob = p.leftRewardProb
        activateRight = (rand <= p.rightRewardProb); % activate right port with prob = p.rightRewardProb
        activateSidePortsForDuration(activateLeft, activateRight, p.centerPokeRewardWindow);
    end
end
end


%% Activate / deactivate side port functions

function activateSidePortsForDuration(activateLeft, activateRight, rewardWindow)
disp(sprintf('activateSidePorts:  R:%g  L:%g', activateRight, activateLeft));
global rightPort leftPort deactivateTimer

% activate only the desired port(s)
if activateRight
    rightPort.activate();
end
if activateLeft
    leftPort.activate();
end
deactivateTimer = executeFunctionWithDelay(@deactivateSidePorts, rewardWindow);
end

function activateBothSidePorts()
disp('activateBothSidePorts')
global rightPort leftPort
rightPort.activate();
leftPort.activate();
end

function deactivateSidePorts()
disp('deactivateSidePorts')
global rightPort leftPort deactivateTimer
try
    stop(deactivateTimer)
end
rightPort.deactivate();
leftPort.deactivate();

end

%% Reward Function
function rewardFunc(portID)
disp('rewardFunc')
global p reactivateTimer
global pokeHistory pokeCount stats
global h
global currBlockReward blockRange currBlockSize


currBlockReward = currBlockReward + 1;
display(currBlockReward)

% log rewarded port to poke history
pokeHistory(pokeCount).REWARD = 1;
%update stats and refresh figures
stats = updatestats(stats,pokeHistory(pokeCount),pokeCount);
cumstats = cumsumstats(stats);
updatestatsfig(cumstats,h,pokeCount);

if p.centerPokeTrigger % if we're in centerPokeTrigger mode
    deactivateSidePorts();
else
    % deactive; wait x seconds; reactive
    deactivateSidePorts();
    reactivateTimer = executeFunctionWithDelay(@activateBothSidePorts, p.minInterTrialInterval);
end

%reupdate reward probabilities if needed.
if currBlockReward >= currBlockSize
    p.leftRewardProb = 1 - p.leftRewardProb;
    p.rightRewardProb = 1 - p.rightRewardProb;
    currBlockReward = 0;
    currBlockSize = randi([min(blockRange),max(blockRange)]);
    display('Reward Probabilities Switched')
    display('Left Reward Prob:')
    p.leftRewardProb
    display('Right Reward Prob:')
    p.rightRewardProb
    display('Current Block Size:')
    global numBlocks
    if p.rightRewardProb >= p.leftRewardProb
        numBlocks.right = numBlocks.right + 1;
    else
        numBlocks.left = numBlocks.left + 1;
    end
    currBlockSize
end


end

%% End Trial Function
function endTrial()
global p
if p.centerPokeTrigger % if we're in centerPokeTrigger mode
    disp('endTrial')
    deactivateSidePorts();
end
end

%% cleanup function is run when program ends (either naturally or after ctl-c)
function triplePortCleanup()
disp('Cleaning up...')

%turn all LEDs off
global centerPort rightPort leftPort
centerPort.ledOff();
rightPort.ledOff();
leftPort.ledOff();

%close log file
global logFileID AllNosePorts
fclose(logFileID);

%deactivate any nose ports (just to make sure)
for n = AllNosePorts
    n{1}.deactivate();
end
AllNosePorts = {};
clearPorts(); %clear nose ports

% prompt user to select directory to save pokeHistory
global info
global p
%if user chose to save the data
if info.save == 1
    global pokeHistory stats
    folderName = info.folderName;
    cd(folderName);
    currDay = datestr(date);
    save(strcat('pokeHistory',currDay,'.mat'),'pokeHistory');
    save(strcat('stats',currDay,'.mat'),'stats');
    savefig('stats.fig');
   %properly formats the parameters and saves them in the same format as
   %the log
    parameters = strcat(info.mouseName,'_parameters');
    baseName = [parameters, '_', int2str(yyyymmdd(datetime)), '_'];
    fileCounter = 1;
    fName = [baseName, int2str(fileCounter), '.mat'];
    while (exist(fName, 'file'))
        fileCounter = fileCounter + 1;
        fName = [baseName, int2str(fileCounter), '.mat'];
    end
    save(fName,'p');
end
close 'Stats Figure'
end

