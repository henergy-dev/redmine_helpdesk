#
# With Rails 3 mail is send with the mail method. Sadly redmine
# uses this method-name too in their mailer. This is the reason
# why we need our own Mailer class.
#
class HelpdeskMailer < ActionMailer::Base
  helper :application

  include Redmine::I18n
  include MacroExpander

  # set the hostname for url_for helper
  def self.default_url_options
    { :host => Setting.host_name, :protocol => Setting.protocol }
  end

  # might be deleted
  if defined?(issue.id) && !issue.id.blank?
    variab1 = "issue.id: " + issue.id.to_s
  else
    variab1 = "issue.id not defined"
  end

  # Sending email notifications to the supportclient
  def email_to_supportclient(issue, params)
    # issue, recipient, journal=nil, text='', copy_to=nil    
    recipient = params[:recipient]
    journal = params[:journal]
    text = params[:text]
    carbon_copy = params[:carbon_copy]    

    redmine_headers 'Project' => issue.project.identifier,
                    'Issue-Id' => issue.id,
                    'Issue-Author' => issue.author.login
    redmine_headers 'Issue-Assignee' => issue.assigned_to.login if issue.assigned_to
    message_id issue
    references issue
    
    subject = "[#{issue.project.name} - ##{issue.id}] #{issue.subject}"
    # Set 'from' email-address to 'helpdesk-sender-email' if available.
    # Falls back to regular redmine behaviour if 'sender' is empty.
    p = issue.project
    s = CustomField.find_by_name('helpdesk-sender-email')
    sender = p.custom_value_for(s).try(:value) if p.present? && s.present?
    # If a custom field with text for the first reply is
    # available then use this one instead of the regular
    r = CustomField.find_by_name('helpdesk-first-reply')
    f = CustomField.find_by_name('helpdesk-email-footer')
    reply  = p.nil? || r.nil? ? '' : p.custom_value_for(r).try(:value)
    footer = p.nil? || f.nil? ? '' : p.custom_value_for(f).try(:value)
    # add carbon copy
    ct = CustomField.find_by_name('copy-to')
    if carbon_copy.nil?
      carbon_copy = issue.custom_value_for(ct).try(:value)
    end
    # add any attachements
    if journal.present? && text.present?
      journal.details.each do |d|
        if d.property == 'attachment'
          a = Attachment.find(d.prop_key)
          begin
            attachments[a.filename] = File.read(a.diskfile)
          rescue
            # ignore rescue
          end
        end
      end
    end
    if @message_id_object
      headers[:message_id] = "<#{self.class.message_id_for(@message_id_object)}>"
    end
    if @references_objects
      headers[:references] = @references_objects.collect {|o| "<#{self.class.references_for(o)}>"}.join(' ')
    end
    # create mail object to deliver
    mail = if text.present? || reply.present?
      # sending out the journal note to the support client
      # or the first reply message
      
      # ---------------------------------------
      
      text_on_date = "In data"
      text_has_written = "Ha scritto"
      old_posts_array = []

        # --- functions ---
        def readableName(author, email)
          if (author.lastname != "Anonymous") 
            return "#{author.firstname} #{author.lastname}"
          else
            return email
          end
        end

        def readableDate(date)
          date = date.to_s
          return date[0...-4]
        end

        # --- queries ---
        Journal.where(:journalized_id => issue.id).where(:journalized_type => "Issue").order("created_on DESC").each do |old_post|

        journal_author = User.find(old_post.user_id)        
        recipient_name = readableName(journal_author, recipient);

        # --- message 
        complete_post = "\n---\n#{text_on_date} #{readableDate(old_post.created_on)} #{recipient_name} #{text_has_written}:\n\n #{old_post.notes}\n\n"

        old_posts_array << complete_post

      end
 
      # --- out of the loop: first post by the customer ---

      original_author = User.find(issue.author_id)
      original_name = readableName(original_author, recipient)
      original_text = issue.description[issue.description.index('</pre>')+6..-1]

      first_post = "\n---\n#{text_on_date} #{readableDate(issue.created_on)} #{original_name} #{text_has_written}:\n #{original_text}\n"
      
      old_posts_array << first_post 
      
      # prevents the last interaction to show up.
      old_posts_array = old_posts_array.drop(1)
      old_posts = old_posts_array.join('')

      t = text.present? ? "#{text}\n\n#{footer}\n\n#{old_posts}" : reply

      # ---------------------------------------

      mail(
        :from     => sender.present? && sender || Setting.mail_from,
        :reply_to => sender.present? && sender || Setting.mail_from,
        :to       => recipient,
        :subject  => subject,
        :body     => expand_macros(t, issue, journal),
        :date     => Time.zone.now,
        :cc       => carbon_copy
      )
    else
      # fallback to a regular notifications email with redmine view
      @issue = issue
      @journal = journal
      @issue_url = url_for(:controller => 'issues', :action => 'show', :id => issue)
      mail(
        :from     => sender.present? && sender || Setting.mail_from,
        :reply_to => sender.present? && sender || Setting.mail_from,
        :to       => recipient,
        :subject  => subject,
        :date     => Time.zone.now,
        :template_path => 'mailer',
        :template_name => 'issue_edit',
        :cc            => carbon_copy
      )
    end
    # return mail object to deliver it
    return mail
  end

  private

  # Returns a Message-Id for the given object
  def self.message_id_for(object)
    Mailer.class_eval do
      token_for(object, true)
    end
  end

  # Returns a uniq token for a given object referenced by all notifications
  # related to this object
  def self.references_for(object)
    Mailer.class_eval do
      token_for(object, false)
    end
  end

  # Appends a Redmine header field (name is prepended with 'X-Redmine-')
  def redmine_headers(h)
    h.each { |k,v| headers["X-Redmine-#{k}"] = v.to_s }
  end

  def message_id(object)
    @message_id_object = object
  end

  def references(object)
    @references_objects ||= []
    @references_objects << object
  end
end
