function sorted = natsort(names)
% NATSORT  Natural-order sort for cell array of strings.
%
%   sorted = natsort(names)
%
%   Sorts strings so that embedded numbers are compared numerically:
%     {'a2', 'a10', 'a1'} -> {'a1', 'a2', 'a10'}
%   instead of lexicographic order which gives {'a1', 'a10', 'a2'}.

    if isempty(names)
        sorted = names;
        return;
    end

    % Extract the first number found in each filename for sorting
    nums = zeros(numel(names), 1);
    prefix = cell(numel(names), 1);
    for i = 1:numel(names)
        tok = regexp(names{i}, '^(.*?)(\d+)(?!.*\d)', 'tokens', 'once');
        if ~isempty(tok)
            prefix{i} = tok{1};
            nums(i) = str2double(tok{2});
        else
            prefix{i} = names{i};
            nums(i) = 0;
        end
    end

    % Sort by prefix first, then by number
    [~, idx] = sortrows([prefix, num2cell(nums)], [1, 2]);
    sorted = names(idx);
end
