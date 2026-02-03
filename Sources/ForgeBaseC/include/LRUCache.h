class LRUCache {
private:
    int _capacity = 0;
    list<int> listKeys;
    unordered_map<int, int> values;
    unordered_map<int, list<int>::iterator> iterators;

    void touch(int key) {
        auto iter = iterators[key];
        listKeys.erase(iter);
        listKeys.push_front(key);
        iterators[key] = listKeys.begin();
    }

public:
    LRUCache(int capacity) {
        _capacity = capacity;
    }
    

    int get(int key) {
        if(!values.count(key)) {
            return -1;
        }
        touch(key);
        return values[key];
    }
    
    void put(int key, int value) {
        if(values.count(key)) {
            values[key] = value;
            touch(key);
        } else {
            listKeys.push_front(key);
            iterators[key] = listKeys.begin();
            values[key] = value;
        }

        if(values.size() > _capacity) {
            int keyToRemove = listKeys.back();
            listKeys.pop_back();
            values.erase(keyToRemove);
            iterators.erase(keyToRemove);
        }
    }
};
