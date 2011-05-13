# == Schema Information
# Schema version: 27
#
# Table name: tasks
#
#  id              :integer(4)      not null, primary key
#  user_id         :integer(4)
#  assigned_to     :integer(4)
#  completed_by    :integer(4)
#  name            :string(255)     default(""), not null
#  asset_id        :integer(4)
#  asset_type      :string(255)
#  priority        :string(32)
#  category        :string(32)
#  bucket          :string(32)
#  due_at          :datetime
#  completed_at    :datetime
#  deleted_at      :datetime
#  created_at      :datetime
#  updated_at      :datetime
#  background_info :string(255)
#
require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Task do

  before(:each) do
    login
  end

  describe "Task/Create" do
    it "should create a new task instance given valid attributes" do
      task = Factory(:task)
      task.should be_valid
      task.errors.should be_empty
    end

    [ nil, Time.now.utc_offset + 3600 ].each do |offset|
      before(:each) do
        adjust_timezone(offset)
      end

      it "should create a task with due date selected from dropdown within #{offset ? 'different' : 'current'} timezone" do
        task = Factory(:task, :due_at => Time.now.end_of_week, :bucket => "due_this_week")
        task.errors.should be_empty
        task.bucket.should == "due_this_week"
        task.due_at.should == Time.zone.now.end_of_week
      end

      it "should create a task with due date selected from the calendar within #{offset ? 'different' : 'current'} timezone" do
        task = Factory(:task, :bucket => "specific_time", :calendar => "01/31/2020")
        task.errors.should be_empty
        task.bucket.should == "specific_time"
        task.due_at.should == Time.parse("2020-01-31")
      end
    end
  end

  describe "Task/Update" do
    it "should update task name" do
      task = Factory(:task, :name => "Hello")
      task.update_attributes({ :name => "World"})
      task.errors.should be_empty
      task.name.should == "World"
    end

    it "should update task category" do
      task = Factory(:task, :category => "call")
      task.update_attributes({ :category => "email" })
      task.errors.should be_empty
      task.category.should == "email"
    end

    it "should reassign the task to another person" do
      him = Factory(:user)
      her = Factory(:user)
      task = Factory(:task, :assigned_to => him.id)
      task.update_attributes( { :assigned_to => her.id } )
      task.errors.should be_empty
      task.assigned_to.should == her.id
      task.assignee.should == her
    end

    it "should reassign the task from another person to myself" do
      him = Factory(:user)
      task = Factory(:task, :assigned_to => him.id)
      task.update_attributes( { :assigned_to => "" } )
      task.errors.should be_empty
      task.assigned_to.should == nil
      task.assignee.should == nil
    end

    [ nil, Time.now.utc_offset + 3600 ].each do |offset|
      before(:each) do
        adjust_timezone(offset)
      end

      it "should update due date based on selected bucket within #{offset ? 'different' : 'current'} timezone" do
        task = Factory(:task, :due_at => Time.now.midnight.tomorrow, :bucket => "due_tomorrow")
        task.update_attributes( { :bucket => "due_this_week" } )
        task.errors.should be_empty
        task.bucket.should == "due_this_week"
        task.due_at.should == Time.zone.now.end_of_week
      end

      it "should update due date if specific calendar date selected within #{offset ? 'different' : 'current'} timezone" do
        task = Factory(:task, :due_at => Time.now.midnight.tomorrow, :bucket => "due_tomorrow")
        task.update_attributes( { :bucket => "specific_time", :calendar => "01/31/2020" } )
        task.errors.should be_empty
        task.bucket.should == "specific_time"
        task.due_at.should == Time.parse("2020-01-31")
      end
    end

  end

  describe "Task/Complete" do
    it "should comlete a task that is overdue" do
      task = Factory(:task, :due_at => 2.days.ago, :bucket => "overdue")
      task.update_attributes(:completed_at => Time.now, :completed_by => @current_user.id)
      task.errors.should be_empty
      task.completed_at.should_not == nil
      task.completor.should == @current_user
    end

    it "should complete a task due sometime in the future" do
      task = Factory(:task, :due_at => Time.now.midnight.tomorrow, :bucket => "due_tomorrow")
      task.update_attributes(:completed_at => Time.now, :completed_by => @current_user.id)
      task.errors.should be_empty
      task.completed_at.should_not == nil
      task.completor.should == @current_user
    end

    it "should complete a task that is due on specific date in the future" do
      task = Factory(:task, :calendar => "10/10/2022", :bucket => "specific_time")
      task.calendar = nil # Calendar is not saved in the database; we need it only to set the :due_at.
      task.update_attributes(:completed_at => Time.now, :completed_by => @current_user.id)
      task.errors.should be_empty
      task.completed_at.should_not == nil
      task.completor.should == @current_user
    end

    it "should complete a task that is due on specific date in the past" do
      task = Factory(:task, :calendar => "10/10/1992", :bucket => "specific_time")
      task.calendar = nil # Calendar is not saved in the database; we need it only to set the :due_at.
      task.update_attributes(:completed_at => Time.now, :completed_by => @current_user.id)
      task.errors.should be_empty
      task.completed_at.should_not == nil
      task.completor.should == @current_user
    end

    it "completion should preserve original due date" do
      due_at = 42.days.ago
      task = Factory(:task, :due_at => due_at, :bucket => "specific_time", :calendar => due_at.to_s)
      task.update_attributes(:completed_at => Time.now, :completed_by => @current_user.id, :calendar => '')
      task.completed?.should == true
      task.due_at.to_i.should == due_at.to_i
    end
  end

  # named_scope :my, lambda { |user| { :conditions => [ "(user_id = ? AND assigned_to IS NULL) OR assigned_to = ?", user.id, user.id ], :include => :assignee } }
  describe "task.my?" do
    it "should match a task created by the user" do
      task = Factory(:task, :user => @current_user, :assignee => nil)
      task.my?(@current_user).should == true
    end

    it "should match a task assigned to the user" do
      task = Factory(:task, :user => Factory(:user), :assignee => @current_user)
      task.my?(@current_user).should == true
    end

    it "should Not match a task not created by the user" do
      task = Factory(:task, :user => Factory(:user))
      task.my?(@current_user).should == false
    end

    it "should Not match a task created by the user but assigned to somebody else" do
      task = Factory(:task, :user => @current_user, :assignee => Factory(:user))
      task.my?(@current_user).should == false
    end
  end

  # named_scope :assigned_by, lambda { |user| { :conditions => [ "user_id = ? AND assigned_to IS NOT NULL AND assigned_to != ?", user.id, user.id ], :include => :assignee } }
  describe "task.assigned_by?" do
    it "should match a task assigned by the user to somebody else" do
      task = Factory(:task, :user => @current_user, :assignee => Factory(:user))
      task.assigned_by?(@current_user).should == true
    end

    it "should Not match a task not created by the user" do
      task = Factory(:task, :user => Factory(:user))
      task.assigned_by?(@current_user).should == false
    end

    it "should Not match a task not assigned to anybody" do
      task = Factory(:task, :assignee => nil)
      task.assigned_by?(@current_user).should == false
    end

    it "should Not match a task assigned to the user" do
      task = Factory(:task, :assignee => @current_user)
      task.assigned_by?(@current_user).should == false
    end
  end

  # named_scope :tracked_by, lambda { |user| { :conditions => [ "user_id = ? OR assigned_to = ?", user.id, user.id ], :include => :assignee } }
  describe "task.tracked_by?" do
    it "should match a task created by the user" do
      task = Factory(:task, :user => @current_user)
      task.tracked_by?(@current_user).should == true
    end

    it "should match a task assigned to the user" do
      task = Factory(:task, :assignee => @current_user)
      task.tracked_by?(@current_user).should == true
    end

    it "should Not match a task that is neither created nor assigned to the user" do
      task = Factory(:task, :user => Factory(:user), :assignee => Factory(:user))
      task.tracked_by?(@current_user).should == false
    end
  end

  describe "named_scopes" do
    context "assigned_to" do
      before :each do
        @user = Factory(:user)
      end
      context "a user object is given as input" do
        it "should return tasks which are assigned to a given user" do
          task = Factory(:task, :assigned_to => @user.id)
          Task.assigned_to(@user).should == [task]
        end
      
        it "should not return tasks which are not assigned to a given user" do
          Factory(:task, :assigned_to => Factory(:user))
          Task.assigned_to(@user).should == []
        end
        it "should order by 'due_at ASC'" do
          task1 = Factory.build(:task, :bucket => "specific_time", :assigned_to => @user.id)
          task1.calendar = 5.days.from_now.to_s
          task1.save
          task2 = Factory.build(:task, :bucket => "specific_time", :assigned_to => @user.id)
          task2.calendar = 2.days.from_now.to_s
          task2.save
          Task.assigned_to(@user).should == [task2, task1]
        end
      end
      context "a user with options is given as input(a hash)" do
        it "should return tasks which are assigned to a given user" do
          task = Factory(:task, :assigned_to => @user.id)
          Task.assigned_to({:user => @user}).should == [task]
        end
        it "should not return tasks which are not assigned to a given user" do
          Factory(:task, :assigned_to => Factory(:user))
          Task.assigned_to({:user => @user}).should == []
        end
        it "should order by 'name ASC'" do
          task1 = Factory(:task, :name => "eat your lunch", :assigned_to => @user.id)
          task2 = Factory(:task, :name => "zebra racing", :assigned_to => @user.id)
          Task.assigned_to({:user => @user, :order => "name ASC"}).should == [task1, task2]
        end
        it "should have a limit of 2" do
          Factory(:task, :name => "eat your lunch", :assigned_to => @user.id)
          Factory(:task, :name => "zebra racing", :assigned_to => @user.id)
          Factory(:task, :name => "dog walking", :assigned_to => @user.id)
          Task.assigned_to({:user => @user, :limit => 2}).count.should == 2
        end
      end
    end
  end
end
