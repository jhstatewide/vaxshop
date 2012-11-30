require 'java'
require 'pstore'
require 'pp'
require 'csv'
require 'bigdecimal'

java_import Java::net.milkbowl.vault.Vault
java_import Java::net.milkbowl.vault.economy.Economy
java_import Java::net.milkbowl.vault.economy.EconomyResponse
java_import Java::net.milkbowl.vault.permission.Permission

import 'org.bukkit.Material'
import 'org.bukkit.inventory.ItemStack'
import 'org.bukkit.util.Vector'
import 'org.bukkit.ChatColor'

require 'bukkit/permissions'

Plugin.is {
  name "VaxShop"
  version "0.1"
  author "vaxgeek"
  commands :vs => {
        :description => "Interact with VaxShop",
        :usage => "/vs",
        :aliases => [ :shop, :vaxshop ]
    }
}
class VaxShop < RubyPlugin
  def onEnable
    @SERVER = org.bukkit.Bukkit.getServer
    @VAULT = server.getPluginManager.getPlugin("Vault")
    @SHOP = Vax::Shop.new
    @LOOKUP = Vax::NameLookuper.new
    print "VaxShop enabled."
    print "Vault is: #{@VAULT.inspect}"
    setup_economy()
    setup_permissions()
  end

  def onDisable
    print "VaxShop disabled."
  end

  def onCommand(sender, command, label, args)
    # puts "#{sender} said #{command} with label #{label} and #{args.to_a.inspect}"
    begin    
      if args.length == 0
        send(sender,"|gCommands: /vs buy,sell,price,help,list")
        return true
      end
        
      if args[0].downcase == "sell"
        
        raise "You must say /vs sell ITEM COUNT PRICE" unless args.length == 4
        
        item = @LOOKUP.item_id(args[1].downcase)
        item = args[1].to_i if item == nil
        # puts "the item is: #{item.inspect}"
        count = args[2].to_i
        # new big decimal, 2 significant sigits...
        price = BigDecimal.new(args[3], 2)
        raise "Count must be greater than 0" if count <= 0
        raise "Price must be greater than 0" if price <= 0

        # see if we have more than 1000 items...
        raise "Too much in stock already! Someone has to buy it first!" if @SHOP.count_items(item) > 1000
        
        worst_price = @SHOP.worst_price(item)
        if worst_price
        	raise "Your price is a ripoff! Price must be lower than #{sprintf("%0.2f", (worst_price * 5).to_f)}! " if price > worst_price * 5
        else
                # prevent first item rip-off
                raise "Your price is a ripoff! Price must be lower than #{@ECONOMY.getBalance(sender.getName)}" if price > @ECONOMY.getBalance(sender.getName)
        end
        
        if inventory_has?(sender, item, count)
          remove_from_inventory(sender, item, count)
          @SHOP.add(:count => count, :item_id => item, :player => sender.getName, :price => price)
        else
          raise "You don't have enough of that item to do that!"
        end
        send(sender, "|gYou have sold #{count} #{@LOOKUP.name(item)} to the shop for #{sprintf("%.2f",price)} each!")
        broadcast("|g#{sender.getName} sold #{count} #{@LOOKUP.name(item)} to the shop for #{sprintf("%.2f",price)} each!")
        
        
      elsif args[0].downcase == "buy"
        
        raise "You must say /vs buy ITEM COUNT" unless args.length == 3
        item_id = @LOOKUP.item_id(args[1].downcase)
        item_id = args[1].to_i if item_id == nil
        count = args[2].to_i
        deal = @SHOP.best_deal(item_id)
        raise "You can't buy less than one!" if count < 1
        raise "You can't buy this from the shop right now!" if deal == nil
        raise "You can't get that many at this price!" if  count > deal[:count]
        # see if the player has enough loot...
        price = deal[:price]
        player_balance = @ECONOMY.getBalance(sender.getName())
        if player_balance >= deal[:price] * count
          # okay, we can afford it!
          # first remove the cash from them...
          @ECONOMY.withdrawPlayer(sender.getName, (price*count))
          @SHOP.remove(:player => deal[:player], :count => count, :item_id => item_id, :price => deal[:price])
          # deposit into the other player's account
          @ECONOMY.depositPlayer(deal[:player], price*count)
          # finally, give to player
          add_to_inventory(sender, item_id, count)
        else
          raise "Sorry, you can't afford that!"
        end
        #send(sender,"|gYou just bought #{count} #{@LOOKUP.name(item_id)} from the shop for a total of #{sprintf("%.2f",price*count)}!")
        broadcast("|g#{sender.getName} just bought #{count} #{@LOOKUP.name(item_id)} from the shop for a total of #{sprintf("%.2f",price*count)}!")
        
      elsif args[0].downcase == "help"
        
      	      send(sender,"|gCommands: /vs buy,sell,price,help,list,name") 
 

      elsif args[0].downcase == "name"
      	      raise "You must specify ID" unless args.length == 2
      	      item_id = args[1].to_i
      	      send(sender,"|gItem id: #{@LOOKUP.name(item_id)}")
      	      
      elsif args[0].downcase == "id"
      	      raise "You must specify name" unless args.length == 2
      	      name = args[1].downcase
      	      send(sender,"|gItem id: #{@LOOKUP.item_id(name)}")
      	      	      
      elsif args[0].downcase == "list"
        
        page = args.length == 2 ? args[1].to_i : 1
        send(sender, "|gPage #{page}:")
        chunk = 4
        start_item = (page - 1) * chunk
        end_item = start_item + chunk
        contents = @SHOP.contents
        end_item = contents.length - 1 if end_item >= contents.length
        
        # puts "Would slice from #{start_item} to #{chunk}"
        contents = contents[start_item .. end_item]
        raise "No items in shop!" if contents == nil or contents.length == 0
        if contents.length > 0
        	# puts contents.inspect
		contents.each do |data|
			send(sender, "|w#{data[:player]} #{@LOOKUP.name(data[:item_id])} x #{data[:count]} for $#{sprintf("%.2f",data[:price])}")
		end
	end
        
        
      elsif args[0].downcase == "price"
        
        raise "You must specify an item ID to get price for!" unless args.length == 2
        item_id = @LOOKUP.item_id(args[1].downcase)
        item_id = args[1].to_i if item_id == nil
        raise "Shop doesn't have any #{@LOOKUP.name(item_id)}" unless @SHOP.has?(item_id)
        best_deal = @SHOP.best_deal(item_id)
        send(sender, "The best price I can get you is: #{best_deal[:count]} #{@LOOKUP.name(best_deal[:item_id])} #{sprintf("%.2f",best_deal[:price])} each from #{best_deal[:player]}")
        
      else
        
        raise "Unknown /vs command! See /vs help!"
        
      end
    rescue => e
      send(sender, "|rERROR: " + e.message)
      print e.inspect
      print e.backtrace.join "\n"
    end
    true
  end

  private
  
  def inventory_has?(player, id, quantity)
    return player.getInventory.contains(id, quantity)
  end
  
  def add_to_inventory(player, item_id, quantity)
    is = ItemStack.new(item_id)
    # ok, now figure out MaxStackSize 
    max_stack_size = is.getMaxStackSize()
    puts "The max stack size is: #{max_stack_size}" 
    if max_stack_size == -1 || quantity <= max_stack_size
       is = ItemStack.new(item_id)
       is.amount = quantity
       player.getInventory.addItem(is)
    else
       (quantity / max_stack_size).times do |i|
          is = ItemStack.new(item_id)
          is.amount = max_stack_size
          player.getInventory.addItem(is)
       end 
    end
  end
  
  def remove_from_inventory(player, item_id, quantity)
      total_removed = 0
      player.getInventory.getContents.each do |is|
        if is && is.getTypeId == item_id && total_removed < quantity
            durability = is.getDurability()
            default_durability = is.getType().getMaxDurability()
            #puts "The durability is #{durability} and the default is #{default_durability}"
            unless is.getDurability() == 0
               raise "Can't sell used goods!" if  is.getDurability() < is.getType().getMaxDurability()
            end
            while is.getAmount >= 0 && total_removed < quantity
                if is.getAmount <= 1
                    player.getInventory.removeItem(is)
                else    
            	   # decrement until nothing...
                   is.setAmount(is.getAmount - 1)
                   # if there's only 1 item in the item stack, destroy it!
                end
                total_removed += 1
            end
        end
      end
    end
  
  def send(sender, message)
    fancy_plug = colorize("|c[|YVAXSHOP|c] |w")
    sender.sendMessage(fancy_plug + colorize(message))
  end
  
  def broadcast(message)
    fancy_plug = colorize("|c[|YVAXSHOP|c] |w")
    @SERVER.broadcastMessage(fancy_plug + colorize(message))
  end
  
  def colorize(s)
      map = {
          '|r' => ChatColor::RED,
          '|R' => ChatColor::DARK_RED,
          '|y' => ChatColor::YELLOW,
          '|Y' => ChatColor::GOLD,
          '|g' => ChatColor::GREEN,
          '|G' => ChatColor::DARK_GREEN,
          '|c' => ChatColor::AQUA,
          '|C' => ChatColor::DARK_AQUA,
          '|b' => ChatColor::BLUE,
          '|B' => ChatColor::DARK_BLUE,
          '|p' => ChatColor::LIGHT_PURPLE,
          '|P' => ChatColor::DARK_PURPLE,
          '|s' => ChatColor::GRAY,
          '|S' => ChatColor::DARK_GRAY,
          '|w' => ChatColor::WHITE,
          '|k' => ChatColor::BLACK,
      }
      
      map.each do|i,v| 
          s = s.gsub(i, v.to_s)
      end

      s
  end

  def setup_permissions
    raise "Vault can't be used" unless @VAULT
    rsp = @SERVER.getServicesManager.getRegistration(Permission.java_class)
    @PERMISSIONS = rsp.getProvider
  end

  def setup_economy
    raise "Vault can't be used" unless @VAULT
    rsp = @SERVER.getServicesManager.getRegistration(Economy.java_class)
    @ECONOMY = rsp.getProvider
  end
end

module Vax

	class NameLookuper
		def initialize
			@id_to_name = Hash.new{|h,k| h[k] = [] }
			@name_to_id = Hash.new{|h,k| h[k] = [] }
			CSV.foreach("plugins/VaxShop/items.csv") do |row|
				name, item_id = row
				# puts "Name is #{name} is equal to #{item_id}"
				@id_to_name[item_id.to_i] << name
				@name_to_id[name] << item_id.to_i
			end
		end
		
		def name(item_id)
			return @id_to_name[item_id].first
		end
		
		def item_id(name)
			return @name_to_id[name.downcase].first
		end
	end
	
  class Stack
    attr_accessor :count
    attr_accessor :item_id
    attr_accessor :player
    attr_accessor :price
  end

  class Shop
    
    PSTORE_FILE = "plugins/VaxShop/VaxShop.pstore"
    
    def initialize
      @STACKS = []
      @PSTORE = PStore.new(PSTORE_FILE)
    end

    def add(options)
      verify_options(options, binding)
      # puts "SHOP is adding #{options.inspect}!"
      player = options[:player]
       
      # find an existing stack with the same price and item ID
      stack = find_stack(options)

      # now add in the item...
      @PSTORE.transaction do
        unless @PSTORE[player]
          @PSTORE[player] = []
        end
        # TODO: see if we have any matching stacks... just increase them
        if stack
          # first remove the stack from the store...
          @PSTORE[player].delete(options)
          # then increase the amount we are about to add...
          options[:count] += stack[:count]
        end
        list = @PSTORE[player]
        list << options
        @PSTORE[player] = list
      end
      
      #puts "Shop contents is: #{self.contents.inspect}"
      
    end
    
    def contents
      datas = []
      @PSTORE.transaction(true) do 
        @PSTORE.roots.each do |root|
	   datas.concat @PSTORE[root]
        end
      end
      return datas
    end

    def count_items(item_id)
       count = 0
       contents.each do |stack|
          count += stack[:count] if stack[:item_id] == item_id 
       end
       return count
    end
    
    # removes some items from a stack in teh store...
    def remove(options)
      verify_options(options, binding)
      found_stack = nil
      contents.each do |stack|
        found_stack = stack if stack[:price] == options[:price] and stack[:item_id] == options[:item_id] and options[:player] == stack[:player]
      end
      #puts "Removing this stack from store: #{found_stack.inspect}"
      raise "Couldn't find a matching stack" unless found_stack
      leftover = 0
      # purge from store...
      # check counts...
      @PSTORE.transaction do
        #puts "Player has this many stacks: #{@PSTORE[options[:player]].length}"
        @PSTORE[options[:player]].each do |stack|
           #puts "Comparing: #{stack.inspect} with #{options.inspect}"
           if stack[:price] == options[:price] and stack[:item_id] == options[:item_id] and stack[:player] == options[:player]
              # puts "Deleting this stack: #{stack.inspect}"
              found_stack = stack 
           end
        end
        @PSTORE[options[:player]].delete(found_stack)
      end
      @PSTORE.transaction(true) do
         #puts "Player now has this many after delete: #{@PSTORE[options[:player]].length}"
      end
      # finally, add it back in!
      @PSTORE.transaction do
         found_stack[:count] -= options[:count]
         if found_stack and found_stack[:count] > 0
           list = @PSTORE[options[:player]] 
           list << found_stack
           @PSTORE[options[:player]] = list
           # puts "Adding back in #{found_stack.inspect} because the count is greater than 0"
         else
           puts "There wasn't enough for me to add the stack back in!"
         end
      end
      @PSTORE.transaction(true) do
        # puts "After readd player has: #{@PSTORE[options[:player]].length}"
      end
    end
    
    def best_price(item_id)
      if best_deal(item_id)
        return best_deal(item_id)[:price]
      end
      return nil
    end
    
    def worst_price(item_id)
    	    items = contents.select {|stack| stack[:item_id] == item_id}
    	    # puts items.inspect
    	    items.sort{|a,b| a[:price] <=> b[:price]}
    	    return nil if items == nil
    	    return nil if items.length == 0
    	    return items[0][:price]
    end
    
    def has?(item_id)
      @PSTORE.transaction(true) do 
        @PSTORE.roots.each do |root|
          list = @PSTORE[root]
          list.each do |data|
            return true if data[:item_id] == item_id
          end
        end
      end
      return false
    end

    # returns a hash we can deduct from...
    def best_deal(item_id)
      best_price_so_far = nil
      best_deal_so_far = nil
      best_count = 0
      contents.each do |data|
        if data[:item_id] == item_id 
          best_price_so_far = data[:price] if best_price_so_far == nil
          best_deal_so_far = data if best_deal_so_far == nil
          # puts "The best deal so far is: #{best_deal_so_far}"
          if data[:price] < best_price_so_far 
            best_price_so_far = data[:price]
            best_deal_so_far = data
            best_count = data[:count]
          elsif data[:price] == best_price_so_far 
            # we had a greater count...
            best_count = data[:count]
            best_deal_so_far = data
          end
        end
      end
      return best_deal_so_far
    end
    
    private
    
    def find_stack(options)
      contents.each do |stack|
        if stack[:item_id] == options[:item_id] && stack[:player] == options[:player] && stack[:price] == options[:price]
          return stack
        end
      end
      # if we didn't find anything
      return nil
    end

    def verify_options(options, caller_binding)
      raise "Must specify :player" unless options[:player]
      raise "Must specify :item_id" unless options[:item_id]
      raise "Must specify :count" unless options[:count]
      eval "player=\"#{options[:player]}\"", caller_binding
      eval "count=#{options[:count]}", caller_binding
      eval "item_id=#{options[:item_id]}", caller_binding
      eval "price=#{options[:price]}", caller_binding if options[:price]
    end
  end
end
