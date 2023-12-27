-- Package BinHeap implements a binary heap which sorts its elements
-- according to a user supplied priority function. It returns the
-- top element in O(1), removes it in O(log n), inserts and deletes
-- elements in O(log n).

local addonName, L = ...;
local prototype = {};
local mt = {
	__index = prototype;
	__metatable = true;
};
BinHeap = {};

local swap, heapify;

-- New creates a new binary heap, using prioFunc to sort elements.
-- The priority function prioFunc(a, b) should return true, if a's
-- priority is higher than b's and false otherwise.
function BinHeap:New(prioFunc)
	assert(type(prioFunc) == "function",
		"Invalid Argument #1 to BinHeap:New(prioFunc), function expected");
	local q = {}
	q.prioFunc = prioFunc
	q.elements = {}
	setmetatable(q, mt)
	
	return q
end

local function parent(i)
	if (i == 1) then
		return 1;
	else
		return math.floor(i/2)
	end
end

local function left(i)
	return 2 * i
end

local function right(i)
	return (2 * i) + 1
end

local function swap(t, i, j)
	local tmp = t[i];
	t[i] = t[j];
	t[j] = tmp;
end

-- heapify restores the heap property of table t starting at index
-- start, using prioFunc to determine element priorites. The function
-- assumes that the sub heaps starting at left(start) and right(start)
-- already are valid binary heaps.
local function heapify(t, prioFunc, start)
	local size = #t
	local cur = start
	while (cur < size) do
		local l = left(cur)
		local r = right(cur)
		local largest = cur
		if l <= size and prioFunc(t[l], t[largest]) then
			largest = l
		end
		if r <= size and prioFunc(t[r], t[largest]) then
			largest = r
		end
		-- the start element is at the correct position, the heap
		-- property has been restored.
		if cur == largest then
			break;
		end
		
		swap(t, cur, largest)
		cur = largest
	end
end

function prototype:Push(element)
	table.insert(self.elements, element)
	
	local cur = #self.elements
	while (cur > 1) do
		local par = parent(cur)
		if self.prioFunc(self.elements[cur], self.elements[par]) then
			swap(self.elements, cur, par)
			cur = par
		else
			break;
		end
	end
end

-- Delete removes all occurences of element from the heap
function prototype:Delete(element)
	local size = #self.elements
	local i = 1
	while i <= size do
		if self.elements[i] == element then
			swap(self.elements, i, size)
			table.remove(self.elements)
			heapify(self.elements, self.prioFunc, i)
			size = size - 1
		else
			i = i + 1
		end
	end
end

-- Pop returns and deletes the heap's top element
function prototype:Pop()
	local size = #self.elements
	if size == 0 then
		return nil
	end
	
	swap(self.elements, 1, size)
	local top = table.remove(self.elements)
	heapify(self.elements, self.prioFunc, 1)

	return top
end

-- Peek returns the heap's top element
function prototype:Peek()
	if #self.elements == 0 then
		return nil
	end
	
	return self.elements[1]
end

function prototype:Size()
	return #self.elements	
end

function prototype:Wipe()
	table.wipe(self.elements)
end
