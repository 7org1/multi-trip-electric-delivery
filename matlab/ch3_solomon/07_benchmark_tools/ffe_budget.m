classdef ffe_budget < handle
%FFE_BUDGET  Count objective evaluations and stop at a budget.
%
%   ctr = ffe_budget(100000);
%   ctr.hit();              % one complete objective evaluation
%   ctr.exhausted()         % true once the budget is spent
%   ctr.used()              % how many were spent
%
% WHY A HANDLE CLASS
%   MATLAB passes ordinary variables by value, so a plain counter incremented
%   inside a helper would be lost on return.  A handle class is shared, so every
%   helper can charge its evaluations to the same budget.
%
% WHAT COUNTS AS ONE EVALUATION
%   One complete objective function computation on one candidate SOLUTION.
%   Partial checks (does this customer fit at this position?) are NOT counted,
%   because their number depends on implementation details rather than on the
%   amount of search performed.  This is what makes the budget comparable
%   across algorithms.

    properties
        n = 0
        budget = inf
    end

    methods
        function obj = ffe_budget(budget)
            if nargin > 0 && ~isempty(budget)
                obj.budget = budget;
            end
        end

        function hit(obj, k)
            if nargin < 2, k = 1; end
            obj.n = obj.n + k;
        end

        function s = exhausted(obj)
            s = obj.n >= obj.budget;
        end

        function s = used(obj)
            s = obj.n;
        end

        function s = left(obj)
            s = max(0, obj.budget - obj.n);
        end
    end
end
