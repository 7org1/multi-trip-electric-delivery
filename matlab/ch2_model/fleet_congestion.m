function [share, speedShare, driveShare] = fleet_congestion(C, trips)
% FLEET_CONGESTION  The three period shares of a whole solution.
%
%   share = [morning, daytime, evening], each the distance weighted average over the
%   trips of the fraction of driving time a trip spends in that period.  These three
%   numbers enter the bandit state, so the operator choice can depend on which part
%   of the day the current plan is exposed to.

nt = numel(trips);
if nt == 0
    share = zeros(3, 1); speedShare = 0; driveShare = 1; return
end
acc = zeros(1, 3);
drive = 0; dist = 0;
for k = 1:nt
    [sh, ~, dh] = congestion(C, trips{k});
    acc = acc + sh * dh;
    drive = drive + dh;
    dist = dist + trip_dist(C, trips{k});
end
if drive > 0
    share = (acc / drive)';
    ms = dist / drive;
else
    share = zeros(3, 1); ms = 0;
end
speedShare = min(1, ms / 40);
driveShare = min(1, drive / 12);
end
