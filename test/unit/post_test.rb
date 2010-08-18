require_relative '../test_helper'

class PostTest < ActiveSupport::TestCase
  setup do
    user = Factory.create(:user)
    CurrentUser.user = user
    CurrentUser.ip_addr = "127.0.0.1"
  end
  
  teardown do
    CurrentUser.user = nil
    CurrentUser.ip_addr = nil
  end
  
  context "Removal:" do
    context "Removing a post" do
      should "duplicate the post in the archive table and remove it from the base table" do
        post = Factory.create(:post)
        
        assert_difference("RemovedPost.count", 1) do
          assert_difference("Post.count", -1) do
            post.remove!
          end
        end
        
        removed_post = RemovedPost.last
        assert_equal(post.tag_string, removed_post.tag_string)
      end
      
      should "decrement the tag counts" do
        post = Factory.create(:post, :tag_string => "aaa")
        assert_equal(1, Tag.find_by_name("aaa").post_count)
        post.remove!
        assert_equal(0, Tag.find_by_name("aaa").post_count)
      end
    end
  end
  
  context "Parenting:" do
    context "Assignining a parent to a post" do
      should "update the has_children flag on the parent" do
        p1 = Factory.create(:post)
        assert(!p1.has_children?, "Parent should not have any children")
        c1 = Factory.create(:post, :parent_id => p1.id)
        p1.reload
        assert(p1.has_children?, "Parent not updated after child was added")
      end
      
      should "update the has_children flag on the old parent" do
        p1 = Factory.create(:post)
        p2 = Factory.create(:post)
        c1 = Factory.create(:post, :parent_id => p1.id)
        c1.parent_id = p2.id
        c1.save
        p1.reload
        p2.reload
        assert(!p1.has_children?, "Old parent should not have a child")
        assert(p2.has_children?, "New parent should have a child")
      end

      should "validate that the parent exists" do
        post = Factory.build(:post, :parent_id => 1_000_000)
        post.save
        assert(post.errors[:parent].any?, "Parent should be invalid")
      end
      
      should "fail if the parent has a parent" do
        p1 = Factory.create(:post)
        c1 = Factory.create(:post, :parent_id => p1.id)
        c2 = Factory.build(:post, :parent_id => c1.id)
        c2.save
        assert(c2.errors[:parent].any?, "Parent should be invalid")
      end
    end
        
    context "Destroying a post with a parent" do
      should "reassign favorites to the parent" do
        p1 = Factory.create(:post)
        c1 = Factory.create(:post, :parent_id => p1.id)
        user = Factory.create(:user)
        c1.add_favorite(user)
        c1.remove!
        p1.reload
        assert(!Favorite.exists?(:post_id => c1.id, :user_id => user.id))
        assert(Favorite.exists?(:post_id => p1.id, :user_id => user.id))
      end

      should "update the parent's has_children flag" do
        p1 = Factory.create(:post)
        c1 = Factory.create(:post, :parent_id => p1.id)
        c1.remove!
        p1.reload
        assert(!p1.has_children?, "Parent should not have children")
      end
    end
    
    context "Destroying a post with" do
      context "one child" do
        should "remove the parent of that child" do
          p1 = Factory.create(:post)
          c1 = Factory.create(:post, :parent_id => p1.id)
          p1.remove!
          c1.reload
          assert_nil(c1.parent)
        end
      end
      
      context "two or more children" do
        should "reparent all children to the first child" do
          p1 = Factory.create(:post)
          c1 = Factory.create(:post, :parent_id => p1.id)
          c2 = Factory.create(:post, :parent_id => p1.id)
          c3 = Factory.create(:post, :parent_id => p1.id)
          p1.remove!
          c1.reload
          c2.reload
          c3.reload
          assert_nil(c1.parent)
          assert_equal(c1.id, c2.parent_id)
          assert_equal(c1.id, c3.parent_id)
        end
      end
    end
    
    context "Undestroying a post with a parent" do
      should "not preserve the parent's has_children flag" do
        p1 = Factory.create(:post)
        c1 = Factory.create(:post, :parent_id => p1.id)
        c1.remove!
        c1 = RemovedPost.last
        c1.unremove!
        c1 = Post.last
        p1.reload
        assert_nil(p1.parent_id)
        assert(!p1.has_children?, "Parent should not have children")
      end
    end
  end

  context "During moderation a post" do
    setup do
      @post = Factory.create(:post)
      @user = Factory.create(:user)
    end
  
    should "be unapproved once and only once" do
      @post.unapprove!("bad", @user.id, "127.0.0.1")
      assert(@post.is_flagged?, "Post should be flagged.")
      assert_not_nil(@post.unapproval, "Post should have an unapproval record.")
      assert_equal("bad", @post.unapproval.reason)
    
      assert_raise(Unapproval::Error) {@post.unapprove!("bad", @user.id, "127.0.0.1")}
    end
  
    should "not unapprove if no reason is given" do
      assert_raise(Unapproval::Error) {@post.unapprove!("", @user.id, "127.0.0.1")}
    end
  
    should "be destroyed" do
      @post.destroy(1, "127.0.0.1")
      assert(@post.is_deleted?, "Post should be deleted.")
    end
  
    should "be approved" do
      @post.approve!(1, "127.0.0.1")
      assert(!@post.is_pending?, "Post should not be pending.")
    
      @deleted_post = Factory.create(:post, :is_deleted => true)
      @deleted_post.approve!(1, "127.0.0.1")
      assert(!@post.is_deleted?, "Post should not be deleted.")
    end
  end

  context "A post version" do
    should "be created on any save" do
      @user = Factory.create(:user)
      @post = Factory.create(:post)
      @reverter = Factory.create(:user)
      assert_equal(1, @post.versions.size)
    
      @post.rating = "e"
      @post.updater_id = @user.id
      @post.updater_ip_addr = "125.0.0.0"
      @post.save
      assert_equal(2, @post.versions.size)
      assert_equal(@user.id, @post.versions.last.updater_id)
      assert_equal("125.0.0.0", @post.versions.last.updater_ip_addr)
      
      @post.revert_to!(PostVersion.first, @reverter.id, "127.0.0.1")
      assert_equal("tag1 tag2", @post.tag_string)
      assert_equal("q", @post.rating)
    end
  end

  context "A post's tags" do
    setup do
      @post = Factory.create(:post)
    end
  
    should "have an array representation" do
      @post.set_tag_string("aaa bbb")
      assert_equal(%w(aaa bbb), @post.tag_array)
      assert_equal(%w(tag1 tag2), @post.tag_array_was)
    end

    should "reset the tag array cache when updated" do
      post = Factory.create(:post, :tag_string => "aaa bbb ccc")
      user = Factory.create(:user)
      assert_equal(%w(aaa bbb ccc), post.tag_array)
      post.tag_string = "ddd eee fff"
      post.updater_id = user.id
      post.updater_ip_addr = "127.0.0.1"
      post.tag_string = "ddd eee fff"
      post.save
      assert_equal("ddd eee fff", post.tag_string)
      assert_equal(%w(ddd eee fff), post.tag_array)
    end

    should "create the actual tag records" do
      assert_difference("Tag.count", 3) do
        post = Factory.create(:post, :tag_string => "aaa bbb ccc")
      end
    end

    should "update the post counts of relevant tag records" do
      post1 = Factory.create(:post, :tag_string => "aaa bbb ccc")
      post2 = Factory.create(:post, :tag_string => "bbb ccc ddd")
      post3 = Factory.create(:post, :tag_string => "ccc ddd eee")
      user = Factory.create(:user)
      assert_equal(1, Tag.find_by_name("aaa").post_count)
      assert_equal(2, Tag.find_by_name("bbb").post_count)
      assert_equal(3, Tag.find_by_name("ccc").post_count)
      post3.tag_string = "xxx"
      post3.updater_id = user.id
      post3.updater_ip_addr = "127.0.0.1"
      post3.save
      assert_equal(1, Tag.find_by_name("aaa").post_count)
      assert_equal(2, Tag.find_by_name("bbb").post_count)
      assert_equal(2, Tag.find_by_name("ccc").post_count)      
      assert_equal(1, Tag.find_by_name("ddd").post_count)      
      assert_equal(0, Tag.find_by_name("eee").post_count)
      assert_equal(1, Tag.find_by_name("xxx").post_count)
    end

    should "be counted" do
      @user = Factory.create(:user)
      @artist_tag = Factory.create(:artist_tag)
      @copyright_tag = Factory.create(:copyright_tag)
      @general_tag = Factory.create(:tag)
      @new_post = Factory.create(:post, :tag_string => "#{@artist_tag.name} #{@copyright_tag.name} #{@general_tag.name}")
      assert_equal(1, @new_post.tag_count_artist)
      assert_equal(1, @new_post.tag_count_copyright)
      assert_equal(1, @new_post.tag_count_general)
      assert_equal(0, @new_post.tag_count_character)
      assert_equal(3, @new_post.tag_count)

      @new_post.tag_string = "babs"
      @new_post.updater_id = @user.id
      @new_post.updater_ip_addr = "127.0.0.1"
      @new_post.save
      assert_equal(0, @new_post.tag_count_artist)
      assert_equal(0, @new_post.tag_count_copyright)
      assert_equal(1, @new_post.tag_count_general)
      assert_equal(0, @new_post.tag_count_character)
      assert_equal(1, @new_post.tag_count)
    end
    
    should "be merged with any changes that were made after loading the initial set of tags part 1" do
      @user = Factory.create(:user)
      @post = Factory.create(:post, :tag_string => "aaa bbb ccc")
          
      # user a adds <ddd>
      @post_edited_by_user_a = Post.find(@post.id)
      @post_edited_by_user_a.old_tag_string = "aaa bbb ccc"
      @post_edited_by_user_a.tag_string = "aaa bbb ccc ddd"
      @post_edited_by_user_a.updater_id = @user.id
      @post_edited_by_user_a.updater_ip_addr = "127.0.0.1"
      @post_edited_by_user_a.save
      
    
      # user b removes <ccc> adds <eee>
      @post_edited_by_user_b = Post.find(@post.id)
      @post_edited_by_user_b.old_tag_string = "aaa bbb ccc"
      @post_edited_by_user_b.tag_string = "aaa bbb eee"
      @post_edited_by_user_b.updater_id = @user.id
      @post_edited_by_user_b.updater_ip_addr = "127.0.0.1"
      @post_edited_by_user_b.save
    
      # final should be <aaa>, <bbb>, <ddd>, <eee>
      @final_post = Post.find(@post.id)      
      assert_equal(%w(aaa bbb ddd eee), Tag.scan_tags(@final_post.tag_string).sort)
    end

    should "be merged with any changes that were made after loading the initial set of tags part 2" do
      # This is the same as part 1, only the order of operations is reversed.
      # The results should be the same.
    
      @user = Factory.create(:user)
      @post = Factory.create(:post, :tag_string => "aaa bbb ccc")
          
      # user a removes <ccc> adds <eee>
      @post_edited_by_user_a = Post.find(@post.id)
      @post_edited_by_user_a.old_tag_string = "aaa bbb ccc"
      @post_edited_by_user_a.tag_string = "aaa bbb eee"
      @post_edited_by_user_a.updater_id = @user.id
      @post_edited_by_user_a.updater_ip_addr = "127.0.0.1"
      @post_edited_by_user_a.save
    
      # user b adds <ddd>
      @post_edited_by_user_b = Post.find(@post.id)
      @post_edited_by_user_b.old_tag_string = "aaa bbb ccc"
      @post_edited_by_user_b.tag_string = "aaa bbb ccc ddd"
      @post_edited_by_user_b.updater_id = @user.id
      @post_edited_by_user_b.updater_ip_addr = "127.0.0.1"
      @post_edited_by_user_b.save
    
      # final should be <aaa>, <bbb>, <ddd>, <eee>
      @final_post = Post.find(@post.id)      
      assert_equal(%w(aaa bbb ddd eee), Tag.scan_tags(@final_post.tag_string).sort)
    end
  end
  
  context "Adding a meta-tag" do
    setup do
      @post = Factory.create(:post)
    end

    should "be ignored" do
      @user = Factory.create(:user)
    
      @post.updater_id = @user.id
      @post.updater_ip_addr = "127.0.0.1"
      @post.tag_string = "aaa pool:1234 pool:test rating:s fav:bob"
      @post.save
      assert_equal("aaa", @post.tag_string)
    end
  end

  context "Favoriting a post" do
    should "update the favorite string" do
      @user = Factory.create(:user)
      @post = Factory.create(:post)
      @post.add_favorite(@user)
      assert_equal("fav:#{@user.name}", @post.fav_string)
    
      @post.remove_favorite(@user)
      assert_equal("", @post.fav_string)
    end
  end
  
  context "Pooling a post" do
    should "work" do
      post = Factory.create(:post)
      pool = Factory.create(:pool)
      post.add_pool(pool)
      assert_equal("pool:#{pool.name}", post.pool_string)
      post.remove_pool(pool)
      assert_equal("", post.pool_string)
    end
  end
  
  context "A post's uploader" do
    should "be defined" do
      post = Factory.create(:post)
      user1 = Factory.create(:user)
      user2 = Factory.create(:user)
      user3 = Factory.create(:user)
      
      post.uploader = user1
      assert_equal("uploader:#{user1.name}", post.uploader_string)
      
      post.uploader_id = user2.id
      assert_equal("uploader:#{user2.name}", post.uploader_string)
      assert_equal(user2.id, post.uploader_id)
      assert_equal(user2.name, post.uploader_name)
    end
  end

  context "A tag search" do
    should "return posts for 1 tag" do
      post1 = Factory.create(:post, :tag_string => "aaa")
      post2 = Factory.create(:post, :tag_string => "aaa bbb")
      post3 = Factory.create(:post, :tag_string => "bbb ccc")
      relation = Post.find_by_tags("aaa")
      assert_equal(2, relation.count)
      assert_equal(post2.id, relation.all[0].id)
      assert_equal(post1.id, relation.all[1].id)
    end

    should "return posts for a 2 tag join" do
      post1 = Factory.create(:post, :tag_string => "aaa")
      post2 = Factory.create(:post, :tag_string => "aaa bbb")
      post3 = Factory.create(:post, :tag_string => "bbb ccc")
      relation = Post.find_by_tags("aaa bbb")
      assert_equal(1, relation.count)
      assert_equal(post2.id, relation.first.id)
    end
  
    should "return posts for 1 tag with exclusion" do
      post1 = Factory.create(:post, :tag_string => "aaa")
      post2 = Factory.create(:post, :tag_string => "aaa bbb")
      post3 = Factory.create(:post, :tag_string => "bbb ccc")
      relation = Post.find_by_tags("aaa -bbb")
      assert_equal(1, relation.count)
      assert_equal(post1.id, relation.first.id)
    end
  
    should "return posts for 1 tag with a pattern" do
      post1 = Factory.create(:post, :tag_string => "aaa")
      post2 = Factory.create(:post, :tag_string => "aaab bbb")
      post3 = Factory.create(:post, :tag_string => "bbb ccc")
      relation = Post.find_by_tags("a*")
      assert_equal(2, relation.count)
      assert_equal(post2.id, relation.all[0].id)
      assert_equal(post1.id, relation.all[1].id)          
    end
  
    should "return posts for 2 tags, one with a pattern" do
      post1 = Factory.create(:post, :tag_string => "aaa")
      post2 = Factory.create(:post, :tag_string => "aaab bbb")
      post3 = Factory.create(:post, :tag_string => "bbb ccc")
      relation = Post.find_by_tags("a* bbb")
      assert_equal(1, relation.count)
      assert_equal(post2.id, relation.first.id)
    end
  
    should "return posts for the <id> metatag" do
      post1 = Factory.create(:post)
      post2 = Factory.create(:post)
      post3 = Factory.create(:post)
      relation = Post.find_by_tags("id:#{post2.id}")
      assert_equal(1, relation.count)
      assert_equal(post2.id, relation.first.id)
      relation = Post.find_by_tags("id:>#{post2.id}")
      assert_equal(1, relation.count)
      assert_equal(post3.id, relation.first.id)
      relation = Post.find_by_tags("id:<#{post2.id}")
      assert_equal(1, relation.count)
      assert_equal(post1.id, relation.first.id)
    end
  
    should "return posts for the <fav> metatag" do
      post1 = Factory.create(:post)
      post2 = Factory.create(:post)
      post3 = Factory.create(:post)
      user = Factory.create(:user)
      post1.add_favorite(user)
      post1.save
      relation = Post.find_by_tags("fav:#{user.name}")
      assert_equal(1, relation.count)
      assert_equal(post1.id, relation.first.id)
    end
  
    should "return posts for the <pool> metatag" do
      post1 = Factory.create(:post)
      post2 = Factory.create(:post)
      post3 = Factory.create(:post)
      pool = Factory.create(:pool)
      post1.add_pool(pool)
      post1.save
      relation = Post.find_by_tags("pool:#{pool.name}")
      assert_equal(1, relation.count)
      assert_equal(post1.id, relation.first.id)
    end
  
    should "return posts for the <uploader> metatag" do
      user = Factory.create(:user)
      post1 = Factory.create(:post, :uploader => user)
      post2 = Factory.create(:post)
      post3 = Factory.create(:post)
      assert_equal("uploader:#{user.name}", post1.uploader_string)
      relation = Post.find_by_tags("uploader:#{user.name}")
      assert_equal(1, relation.count)
      assert_equal(post1.id, relation.first.id)
    end
  
    should "return posts for a list of md5 hashes" do
      post1 = Factory.create(:post, :md5 => "abcd")
      post2 = Factory.create(:post)
      post3 = Factory.create(:post)
      relation = Post.find_by_tags("md5:abcd")
      assert_equal(1, relation.count)
      assert_equal(post1.id, relation.first.id)
    end
  
    should "filter out deleted posts by default" do
      post1 = Factory.create(:post, :is_deleted => true)
      post2 = Factory.create(:post, :is_deleted => true)
      post3 = Factory.create(:post, :is_deleted => false)
      relation = Post.find_by_tags("")
      assert_equal(1, relation.count)
      assert_equal(post3.id, relation.first.id)
    end
  
    should "return posts for a particular status" do
      post1 = Factory.create(:post, :is_deleted => true)
      post2 = Factory.create(:post, :is_deleted => false)
      post3 = Factory.create(:post, :is_deleted => false)
      relation = Post.find_by_tags("status:deleted")
      assert_equal(1, relation.count)
      assert_equal(post1.id, relation.first.id)
    end
  
    should "return posts for a source search" do
      post1 = Factory.create(:post, :source => "abcd")
      post2 = Factory.create(:post, :source => "abcdefg")
      post3 = Factory.create(:post, :source => "xyz")
      relation = Post.find_by_tags("source:abcde")
      assert_equal(1, relation.count)
      assert_equal(post2.id, relation.first.id)
    end
  
    should "return posts for a tag subscription search"
  
    should "return posts for a particular rating" do
      post1 = Factory.create(:post, :rating => "s")
      post2 = Factory.create(:post, :rating => "q")
      post3 = Factory.create(:post, :rating => "e")
      relation = Post.find_by_tags("rating:e")
      assert_equal(1, relation.count)
      assert_equal(post3.id, relation.first.id)
    end
  
    should "return posts for a particular negated rating" do
      post1 = Factory.create(:post, :rating => "s")
      post2 = Factory.create(:post, :rating => "s")
      post3 = Factory.create(:post, :rating => "e")
      relation = Post.find_by_tags("-rating:s")
      assert_equal(1, relation.count)
      assert_equal(post3.id, relation.first.id)
    end
  
    should "return posts ordered by a particular attribute" do
      post1 = Factory.create(:post, :rating => "s")
      post2 = Factory.create(:post, :rating => "s")
      post3 = Factory.create(:post, :rating => "e", :score => 5, :image_width => 1000)
      relation = Post.find_by_tags("order:id")
      assert_equal(post1.id, relation.first.id)
      relation = Post.find_by_tags("order:mpixels")
      assert_equal(post3.id, relation.first.id)
      relation = Post.find_by_tags("order:landscape")
      assert_equal(post3.id, relation.first.id)      
    end
  end

  context "Voting on a post" do
    should "not allow duplicate votes" do
      user = Factory.create(:user)
      post = Factory.create(:post)
      assert_nothing_raised {post.vote!(user, true)}
      assert_raise(PostVote::Error) {post.vote!(user, true)}
      post.reload
      assert_equal(1, PostVote.count)
      assert_equal(1, post.score)
    end
  end
end
