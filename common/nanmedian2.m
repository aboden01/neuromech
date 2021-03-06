function m = nanmedian2(x,dim)

if nargin == 1
    if (isrow(x))
        dim = 2;
    else
        dim = 1;
    end
end

ord = [dim 1:dim-1 dim+1:ndims(x)];
x = permute(x,ord);

sz = size(x);
m = zeros([1 sz(2:end)]);

good = isfinite(x);

n = prod(sz(2:end));
for i = 1:n
    m(1,i) = median(x(good(:,i),i));
end

m = ipermute(m,ord);

    
    

