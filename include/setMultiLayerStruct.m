function [structure] = setMultiLayerStruct(data, n_columns)
    
    %get the maximum number of activities

    act = 0;
    
    for i=1:height(data)
        if (data(i,1)>act)
            act = data(i,1);
        end
    end
    %%
    %To implement> sort data for task id
    
    %creation of the empty structure
    for j=1:act
        disp("WIDTH : " + width(data));
        structure{j} = zeros(1, n_columns,width(data)-1);
    end
    
    %Filling the multi-dimensional matrices structure with data
    for i = 1:width(structure)
        disp("NEW DATA");
        buffer = 1+(sum(data(:,1)<=i));
        for layer = 2:width(data)
            for element = 1:(sum(data(:,1) == i)/n_columns)
                disp(buffer);
                structure{i}(element,:, layer-1) = data(buffer:buffer+n_columns-1, layer).';
                buffer = buffer + n_columns;
            end
        end
    end









end