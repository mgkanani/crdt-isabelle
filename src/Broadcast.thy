section\<open>Implementation of Causal Broadcast Protocol\<close>

theory
  Broadcast
imports
  Execution
  Network
  Util
begin

subsection\<open>Causal broadcasts using vector timestamps\<close>

type_synonym 'nodeid msgid = "'nodeid \<times> nat"

record ('nodeid, 'op) message =
  msg_id   :: "'nodeid msgid"
  msg_deps :: "'nodeid \<Rightarrow> nat"
  msg_op   :: "'op"

type_synonym ('nodeid, 'op, 'state) node_state = "(('nodeid, 'op) message event, 'state option) node"

definition filter_bcast :: "('nodeid, 'op) message event list \<Rightarrow> ('nodeid, 'op) message list" where
  "filter_bcast evts \<equiv> List.map_filter (\<lambda>e. case e of Broadcast m \<Rightarrow> Some m | _ \<Rightarrow> None) evts"

definition filter_deliv :: "('nodeid, 'op) message event list \<Rightarrow> ('nodeid, 'op) message list" where
  "filter_deliv evts \<equiv> List.map_filter (\<lambda>e. case e of Deliver m \<Rightarrow> Some m | _ \<Rightarrow> None) evts"

definition op_history :: "('nodeid, 'op) message event list \<Rightarrow> ('nodeid msgid \<times> 'op) event list" where
  "op_history hist \<equiv> map (\<lambda>evt. case evt of
      Broadcast msg \<Rightarrow> Broadcast (msg_id msg, msg_op msg) |
      Deliver   msg \<Rightarrow> Deliver   (msg_id msg, msg_op msg)
    ) hist"

definition causal_deps :: "('nodeid, 'op, 'state) node_state \<Rightarrow> 'nodeid \<Rightarrow> nat" where
  "causal_deps state \<equiv> foldl
    (\<lambda>map msg. case msg_id msg of (node, seq) \<Rightarrow> map(node := seq))
    (\<lambda>n. 0) (filter_deliv (fst state))"

definition deps_leq :: "('nodeid \<Rightarrow> nat) \<Rightarrow> ('nodeid \<Rightarrow> nat) \<Rightarrow> bool" where
  "deps_leq left right \<equiv> \<forall>node::'nodeid. left node \<le> right node"

definition causally_ready :: "('nodeid, 'op, 'state) node_state \<Rightarrow> ('nodeid, 'op) message \<Rightarrow> bool" where
  "causally_ready state msg \<equiv>
     deps_leq (msg_deps msg) (causal_deps state) \<and>
     (case msg_id msg of (sender, seq) \<Rightarrow> seq = Suc(causal_deps state sender))"

definition next_msgid :: "'nodeid \<Rightarrow> ('nodeid, 'op, 'state) node_state \<Rightarrow> 'nodeid msgid" where
  "next_msgid sender state \<equiv> (sender, Suc (length (filter_bcast (fst state))))"

locale cbcast_protocol_base = executions _ valid_msg
  for valid_msg :: "'nodeid \<Rightarrow> ('nodeid, 'op, 'state) node_state \<Rightarrow> ('nodeid, 'op) message set" +
  fixes initial_state :: "'state"
  and interp :: "'op \<Rightarrow> 'state \<rightharpoonup> 'state"
  and valid_ops :: "'nodeid \<Rightarrow> 'state \<Rightarrow> 'op set"

definition (in cbcast_protocol_base) valid_msgs ::
  "'nodeid \<Rightarrow> ('nodeid, 'op, 'state) node_state \<Rightarrow> ('nodeid, 'op) message set" where
  "valid_msgs sender state \<equiv> case snd state of None \<Rightarrow> {} | Some s \<Rightarrow>
     (\<lambda>oper. \<lparr>msg_id   = next_msgid sender state,
              msg_deps = causal_deps state,
              msg_op   = oper\<rparr>
     ) ` valid_ops sender s"

definition (in cbcast_protocol_base) protocol_send ::
  "'nodeid \<Rightarrow> ('nodeid, 'op, 'state) node_state \<Rightarrow> ('nodeid, 'op) message \<Rightarrow> ('nodeid, 'op, 'state) node_state" where
  "protocol_send sender state msg \<equiv> case snd state of None \<Rightarrow> ([], None) | Some s \<Rightarrow>
     ([Broadcast msg, Deliver msg], interp (msg_op msg) s)"

definition (in cbcast_protocol_base) protocol_recv ::
  "'nodeid \<Rightarrow> ('nodeid, 'op, 'state) node_state \<Rightarrow> ('nodeid, 'op) message \<Rightarrow> ('nodeid, 'op, 'state) node_state" where
  "protocol_recv recipient state msg \<equiv>
     if causally_ready state msg
     then case snd state of
       None   \<Rightarrow> ([], None) |
       Some s \<Rightarrow> ([Deliver msg], interp (msg_op msg) s)
     else ([], snd state)"

locale cbcast_protocol = cbcast_protocol_base
  "\<lambda>n. Some initial_state"
  "cbcast_protocol_base.protocol_send interp"
  "cbcast_protocol_base.protocol_recv interp"
  "cbcast_protocol_base.valid_msgs valid_ops" _ _ valid_ops
  for valid_ops :: "'nodeid \<Rightarrow> 'state \<Rightarrow> 'op set" +
  fixes config :: "('nodeid, ('nodeid, 'op) message, ('nodeid, 'op) message event, 'state option) system"
  assumes valid_execution: "execution config"

definition (in cbcast_protocol) history :: "'nodeid \<Rightarrow> ('nodeid, 'op) message event list" where
  "history i \<equiv> fst (snd config i)"

definition (in cbcast_protocol) all_messages :: "('nodeid, 'op) message set" where
  "all_messages \<equiv> fst config"

definition (in cbcast_protocol) broadcasts :: "'nodeid \<Rightarrow> ('nodeid, 'op) message list" where
  "broadcasts i \<equiv> List.map_filter (\<lambda>e. case e of Broadcast m \<Rightarrow> Some m | _ \<Rightarrow> None) (history i)"

definition (in cbcast_protocol) deliveries :: "'nodeid \<Rightarrow> ('nodeid, 'op) message list" where
  "deliveries i \<equiv> List.map_filter (\<lambda>e. case e of Deliver m \<Rightarrow> Some m | _ \<Rightarrow> None) (history i)"

definition (in cbcast_protocol) valid_op_msgs :: "'nodeid \<Rightarrow> 'state \<Rightarrow> ('nodeid msgid \<times> 'op) set" where
  "valid_op_msgs node state \<equiv> undefined"


subsection\<open>Proof that this protocol satisfies the causal network assumptions\<close>

lemma (in cbcast_protocol) broadcast_origin:
  assumes "execution conf"
    and "fst (snd conf i) = xs @ Broadcast msg # ys"
    and "Broadcast msg \<notin> set xs"
  shows "\<exists>pre before after suf state oper evts.
    config_evolution conf (pre @ [before, after] @ suf) \<and>
    snd (snd before i) = Some state \<and>
    oper \<in> valid_ops i state \<and>
    msg = \<lparr>msg_id   = next_msgid i (snd before i),
           msg_deps = causal_deps (snd before i),
           msg_op   = oper\<rparr> \<and>
    evts = fst (snd before i) @ [Broadcast msg, Deliver msg] \<and>
    after = (insert msg (fst before), (snd before)(i := (evts, interp (msg_op msg) state))) \<and>
    fst (snd before i) = xs"
  using assms apply -
  apply(frule config_evolution_exists, erule exE)
  apply(subgoal_tac "Broadcast msg \<in> set (fst (snd conf i))") defer apply(simp)
  apply(frule_tac evt="Broadcast msg" and i=i and xs=xs and ys=ys in event_origin)
  apply(simp add: history_def, simp)
  apply((erule exE)+, (erule conjE)+)
  apply(rule_tac x=pre in exI, erule disjE)
  apply(simp add: send_step_def case_prod_beta)
  apply(erule unpack_let)+
  apply(simp add: case_prod_beta protocol_send_def split: if_split_asm)
  apply(erule unpack_let)
  apply(subgoal_tac "sender=i") prefer 2 apply force
  apply(case_tac "snd (snd before i) = None", force)
  apply(subgoal_tac "fst (snd after i) = fst (snd before i) @ [Broadcast msga, Deliver msga]")
  prefer 2 apply force
  apply(subgoal_tac "msga=msg") prefer 2 apply simp
  apply(subgoal_tac "msg \<in> valid_msgs i (snd before i)")
  prefer 2 apply(simp add: some_set_memb)
  apply(rule_tac x="fst before" in exI, rule_tac x="snd before" in exI)
  apply(rule_tac x="fst after" in exI, rule_tac x="snd after" in exI)
  apply(rule conjI, force)
  apply(rule_tac x="the (snd (snd before i))" in exI)
  apply(rule conjI, force)
  apply(rule_tac x="msg_op msg" in exI)
  apply(subgoal_tac "valid_ops i (the (snd (snd before i))) \<noteq> {}")
  prefer 2 apply(simp add: valid_msgs_def, force)
  apply(subgoal_tac "msg \<in> (\<lambda>oper.
             \<lparr>msg_id   = next_msgid i (snd before i),
              msg_deps = causal_deps (snd before i),
              msg_op   = oper\<rparr>) ` valid_ops i (the (snd (snd before i)))")
  prefer 2 apply(simp add: valid_msgs_def, force)
  apply(subgoal_tac "msg_op msg \<in> valid_ops i (the (snd (snd before i)))")
  prefer 2 apply force
  apply((rule conjI, force)+, force)
  apply(simp add: recv_step_def protocol_recv_def case_prod_beta split: if_split_asm)
  apply(erule unpack_let)+
  apply(subgoal_tac "recipient=i")
  apply(case_tac "causally_ready (snd before recipient) msga")
  apply(case_tac "snd (snd before i) = None", force+)
done

lemma (in cbcast_protocol) broadcast_msg_eq:
  shows "(\<exists>i. Broadcast msg \<in> set (history i)) \<longleftrightarrow> msg \<in> all_messages"
  using valid_execution apply -
  apply(simp add: all_messages_def)
  apply(rule iffI, erule exE)
  apply(subgoal_tac "\<exists>es1 es2. history i = es1 @ Broadcast msg # es2 \<and> Broadcast msg \<notin> set es1")
  prefer 2 apply(meson split_list_first)
  apply((erule exE)+, erule conjE, simp add: history_def)
  apply(drule_tac broadcast_origin, simp, simp, (erule exE)+, (erule conjE)+)
  apply(subgoal_tac "msg \<in> fst after")
  apply(insert message_set_monotonic)[1]
  apply(erule_tac x="config" in meta_allE)
  apply(erule_tac x="pre @ [before]" in meta_allE, simp, simp)
  apply(insert valid_execution, drule config_evolution_exists, erule exE)
  apply(drule message_origin, simp, (erule exE)+, (erule conjE)+)
  apply(rule_tac x=sender in exI)
  apply(case_tac "snd (snd before sender) = None", simp add: valid_msgs_def)
  apply(subgoal_tac "Broadcast msg \<in> set evts") defer
  apply(simp add: protocol_send_def, force)
  apply(subgoal_tac "Broadcast msg \<in> set (fst (snd config sender))")
  apply(simp add: history_def)
  apply(subgoal_tac "\<exists>xs. fst (snd after sender) @ xs = fst (snd config sender)")
  apply(simp add: protocol_send_def)
  apply(metis (no_types, lifting) append.assoc append_Cons in_set_conv_decomp)
  apply(insert history_monotonic)[1]
  apply(erule_tac x="config" in meta_allE)
  apply(erule_tac x="pre @ [before]" in meta_allE)
  apply(erule_tac x="after" in meta_allE)
  apply(erule_tac x="suf" in meta_allE)
  apply(erule_tac x="sender" in meta_allE, simp)
done

lemma (in cbcast_protocol) filter_bcast_events:
  shows "msg \<in> set (filter_bcast hist) \<longleftrightarrow> Broadcast msg \<in> set hist"
  apply(induction hist)
  apply(simp add: filter_bcast_def map_filter_simps(2))
  apply(case_tac a, case_tac "x1=msg")
  apply(rule iffI, metis list.set_intros(1))
  apply(simp_all add: filter_bcast_def map_filter_simps(1))
done

lemma (in cbcast_protocol) broadcasts_history_eq:
  shows "Broadcast msg \<in> set (history i) \<longleftrightarrow> msg \<in> set (broadcasts i)"
  apply(rule iffI, simp add: broadcasts_def map_filter_def, force)
  apply(metis broadcasts_def filter_bcast_def filter_bcast_events)
done

lemma op_history_append:
  shows "op_history (h1 @ h2) = op_history h1 @ op_history h2"
by(simp add: op_history_def)

lemma op_history_broadcast:
  shows "op_history [Broadcast msg] = [Broadcast (msg_id msg, msg_op msg)]"
by(simp add: op_history_def)

lemma op_history_deliver:
  shows "op_history [Deliver msg] = [Deliver (msg_id msg, msg_op msg)]"
by(simp add: op_history_def)

lemma (in cbcast_protocol) op_history_filter_bcast:
  assumes "Broadcast (idx, oper) \<in> set (op_history hist)"
  shows "\<exists>msg. msg \<in> set (filter_bcast hist) \<and> msg_id msg = idx \<and> msg_op msg = oper"
  apply(subgoal_tac "\<exists>msg. Broadcast msg \<in> set hist \<and> msg_id msg = idx \<and> msg_op msg = oper")
  using filter_bcast_events apply blast
  using assms apply(induction hist, simp add: op_history_def)
  apply(case_tac a, case_tac "msg_id x1 = idx \<and> msg_op x1 = oper", force)
  apply(subgoal_tac "Broadcast (idx, oper) \<in> set (op_history hist)", force)
  apply(subgoal_tac "op_history [a] = [Broadcast (msg_id x1, msg_op x1)]")
  apply(subgoal_tac "Broadcast (idx, oper) \<in> set (op_history [a] @ op_history hist)")
  apply(force, metis append_Cons append_self_conv2 op_history_append)
  apply(simp add: op_history_def)
  apply(subgoal_tac "Broadcast (idx, oper) \<in> set (op_history hist)", force)
  apply(subgoal_tac "op_history [a] = [Deliver (msg_id x2, msg_op x2)]")
  apply(subgoal_tac "Broadcast (idx, oper) \<in> set (op_history [a] @ op_history hist)")
  apply(force, metis append_Cons append_self_conv2 op_history_append)
  apply(simp add: op_history_def)
done

lemma (in cbcast_protocol) broadcast_node_id:
  assumes "Broadcast msg \<in> set (history i)"
  shows "fst (msg_id msg) = i"
  using assms valid_execution apply -
  apply(subgoal_tac "\<exists>es1 es2. history i = es1 @ Broadcast msg # es2 \<and> Broadcast msg \<notin> set es1")
  prefer 2 apply(meson split_list_first)
  apply((erule exE)+, erule conjE, simp add: history_def)
  apply(drule broadcast_origin, simp, simp, simp add: next_msgid_def)
  apply(metis fst_conv select_convs(1))
done

lemma (in cbcast_protocol) broadcast_msg_id_first:
  assumes "execution conf"
    and "fst (snd conf i) = pre @ Broadcast msg # suf"
    and "Broadcast msg \<notin> set pre"
  shows "msg_id msg = (i, Suc (length (filter_bcast pre)))"
  using assms apply -
  apply(frule config_evolution_exists, erule exE)
  apply(subgoal_tac "Broadcast msg \<in> set (fst (snd conf i))") defer
  using filter_bcast_events apply force
  apply(drule broadcast_origin, simp, simp, (erule exE)+)
  apply(simp add: next_msgid_def)
done

lemma (in cbcast_protocol) history_invariant:
  assumes "execution conf"
    and "P ({}, \<lambda>n. ([], Some initial_state)) []"
    and "\<And>conf conf' hist. P conf hist \<Longrightarrow> P conf' hist"
    and "\<And>conf conf' hist msg oper. P conf hist \<Longrightarrow>
       execution conf \<Longrightarrow>
       hist = fst (snd conf i) \<Longrightarrow>
       msg_id msg = next_msgid i (snd conf i) \<Longrightarrow>
       msg_deps msg = causal_deps (snd conf i) \<Longrightarrow>
       P conf' (hist @ [Broadcast msg, Deliver msg])"
    and "\<And>conf conf' hist msg oper. P conf hist \<Longrightarrow>
       execution conf \<Longrightarrow>
       hist = fst (snd conf i) \<Longrightarrow>
       causally_ready (snd conf i) msg \<Longrightarrow>
       P conf' (hist @ [Deliver msg])"
  shows "P conf (fst (snd conf i))"
  using assms(1) apply -
  apply(drule_tac P="\<lambda>conf. P conf (fst (snd conf i))" in evolution_invariant)
  using assms(2) apply(simp add: initial_conf_def)
  prefer 2 apply blast
  apply(rule conjI)
  apply(subgoal_tac "\<exists>conf'. send_step conf = conf'")
  prefer 2 apply(simp, erule exE)
  apply(subgoal_tac "P conf' (fst (snd conf' i))", simp)
  apply(subst (asm) send_step_def)
  apply(simp add: case_prod_beta)
  apply(erule unpack_let)+
  apply(simp add: case_prod_beta protocol_send_def split: if_split_asm)
  apply(erule unpack_let)
  apply(case_tac "sender=i")
  apply(case_tac "\<exists>s. snd (snd conf i) = Some s", erule exE)
  apply(insert assms(4))[1]
  apply(subgoal_tac "msg \<in> (\<lambda>oper.
             \<lparr>msg_id   = next_msgid i (snd conf i),
              msg_deps = causal_deps (snd conf i),
              msg_op   = oper\<rparr>) ` valid_ops i s", force)
  apply(frule some_set_memb, simp add: valid_msgs_def)
  apply(insert assms(3))[1]
  apply(subgoal_tac "snd (snd conf i) = None")
  apply(simp add: valid_msgs_def, blast)
  apply(insert assms(3), force)[1]
  apply(subgoal_tac "\<exists>conf'. recv_step conf = conf'")
  prefer 2 apply(simp, erule exE)
  apply(subgoal_tac "P conf' (fst (snd conf' i))", simp)
  apply(subst (asm) recv_step_def)
  apply(simp add: case_prod_beta protocol_recv_def split: if_split_asm)
  apply(erule unpack_let)+
  apply(simp split: if_split_asm)
  apply(case_tac "snd (snd conf i) = None")
  apply(insert assms(3))[1]
  apply(erule_tac x="conf" in meta_allE)
  apply(erule_tac x="fst (snd conf i)" in meta_allE)
  apply(simp add: valid_msgs_def, force)
  apply(case_tac "recipient=i")
  apply(insert assms(5))[1]
  apply(erule_tac x="conf" in meta_allE)
  apply(erule_tac x="fst (snd conf i)" in meta_allE)
  apply(simp add: valid_msgs_def, force)
  using assms(3) apply force
done

lemma (in cbcast_protocol) broadcast_msg_id:
  assumes "execution conf"
    and "sent = filter_bcast (fst (snd conf i))"
    and "idx < length sent"
  shows "msg_id (sent ! idx) = (i, Suc idx)"
  using assms apply -
  apply(drule_tac i=i and conf=conf and P="\<lambda>conf hist.
           idx < length (filter_bcast hist) \<longrightarrow>
           msg_id ((filter_bcast hist) ! idx) = (i, Suc idx)"
        in history_invariant)
  apply(metis equals0D filter_bcast_events nth_mem set_empty, simp)
  prefer 2 apply(simp add: filter_bcast_def map_filter_def)
  prefer 2 apply simp
  apply(rule impI)
  apply(subgoal_tac "filter_bcast (hist @ [Broadcast msg, Deliver msg]) =
          (filter_bcast hist) @ [msg]")
  defer apply(simp add: filter_bcast_def map_filter_def)
  apply(case_tac "idx < length (filter_bcast hist)")
  apply(simp add: nth_append)
  apply(subgoal_tac "idx = length (filter_bcast hist)")
  apply(auto simp add: next_msgid_def)
done

lemma bcast_append_length:
  shows "length (filter_bcast (xs @ ys)) =
     length (filter_bcast (xs)) + length (filter_bcast (ys))"
by(simp add: filter_bcast_def map_filter_append)

lemma (in cbcast_protocol) broadcast_id_unique:
  assumes "history i = pre @ [Broadcast m1] @ mid @ [Broadcast m2] @ suf"
  shows "msg_id m1 \<noteq> msg_id m2"
  using assms valid_execution apply(simp add: history_def)
  apply(subgoal_tac "filter_bcast (fst (snd config i)) =
    filter_bcast pre @ m1 # filter_bcast mid @ m2 # filter_bcast suf")
  defer apply(simp add: filter_bcast_def map_filter_def)
  apply(subgoal_tac "length (filter_bcast pre) < length (filter_bcast (fst (snd config i)))")
  defer apply simp
  apply(subgoal_tac "filter_bcast (fst (snd config i)) ! length (filter_bcast pre) = m1")
  defer apply simp
  apply(subgoal_tac "msg_id m1 = (i, Suc (length (filter_bcast pre)))")
  defer using broadcast_msg_id apply blast
  apply(subgoal_tac "length (filter_bcast pre @ m1 # filter_bcast mid) <
    length (filter_bcast (fst (snd config i)))")
  defer apply simp
  apply(subgoal_tac "filter_bcast (fst (snd config i)) !
    length (filter_bcast pre @ m1 # filter_bcast mid) = m2")
  defer apply(rule nth_list_item, simp)
  apply(subgoal_tac "msg_id m2 = (i, Suc (length (filter_bcast pre @ m1 # filter_bcast mid)))")
  apply force
  using broadcast_msg_id apply blast
done

lemma (in cbcast_protocol) msg_id_distinct:
  assumes "Broadcast m1 \<in> set (history j)"
    and "Broadcast m2 \<in> set (history j)"
    and "msg_id m1 = msg_id m2"
  shows "m1 = m2"
  using assms apply -
  apply(drule_tac x="Broadcast m1" in list_first_index)
  apply(drule_tac x="Broadcast m2" in list_first_index)
  apply((erule_tac exE)+, (erule_tac conjE)+)
  apply(case_tac "i = ia", fastforce)
  apply(subgoal_tac "msg_id m1 \<noteq> msg_id m2", blast)
  apply(subgoal_tac "pre = take i (history j)")
  prefer 2 apply(simp add: append_eq_conv_conj)
  apply(subgoal_tac "prea = take ia (history j)")
  prefer 2 apply fastforce
  apply(case_tac "i < ia")
  apply(subgoal_tac "ia-i-1 \<ge> 0") prefer 2 apply blast
  apply(subgoal_tac "\<exists>ms. prea = pre @ [Broadcast m1] @ ms", erule exE)
  apply(subgoal_tac "history j = pre @ [Broadcast m1] @ ms @ [Broadcast m2] @ sufa")
  using broadcast_id_unique apply(force, force)
  apply(rule_tac x="take (ia-i-1) suf" in exI)
  apply(metis append.left_neutral append_Cons diff_is_0_eq diffs0_imp_equal
    less_imp_le_nat take_Cons' take_all take_append)
  apply(subgoal_tac "ia < i") prefer 2 apply force
  apply(subgoal_tac "ia-i-1 \<ge> 0") prefer 2 apply blast
  apply(subgoal_tac "\<exists>ms. pre = prea @ [Broadcast m2] @ ms", erule exE)
  apply(subgoal_tac "history j = prea @ [Broadcast m2] @ ms @ [Broadcast m1] @ suf")
  using broadcast_id_unique apply(force, force)
  apply(rule_tac x="take (i-ia-1) sufa" in exI)
  apply(metis append.left_neutral append_Cons diff_is_0_eq diffs0_imp_equal
    less_imp_le_nat take_Cons' take_all take_append)
done

lemma (in cbcast_protocol) msg_id_unique:
  assumes "Broadcast m1 \<in> set (history i)"
      and "Broadcast m2 \<in> set (history j)"
      and "msg_id m1 = msg_id m2"
    shows "i = j \<and> m1 = m2"
  using assms apply -
  apply(case_tac "i=j")
  using msg_id_distinct apply blast
  apply(subgoal_tac "fst (msg_id m1) = i")
  apply(subgoal_tac "fst (msg_id m2) = j", force)
  using broadcast_node_id apply fastforce+
done

(*
inductive rev_distinct :: "'a list \<Rightarrow> bool" where
  "rev_distinct []" |
  "\<lbrakk> rev_distinct list; x \<notin> set list \<rbrakk> \<Longrightarrow> rev_distinct (list @ [x])"

lemma rev_distinct_equiv:
  shows "rev_distinct xs \<longleftrightarrow> distinct xs"
  apply(rule iffI)
  apply(induction xs rule: rev_induct, simp)
  using rev_distinct.cases apply auto[1]
  apply(induction xs rule: rev_induct)
  apply(auto simp add: rev_distinct.intros)
done
*)

lemma (in cbcast_protocol) broadcast_distinct:
  assumes "execution conf"
    and "msg_id msg = next_msgid i (snd conf i)"
  shows "Broadcast (msg_id msg, msg_op msg) \<notin> set (op_history (fst (snd conf i)))"
  using assms apply(simp add: next_msgid_def)
  apply(subgoal_tac "\<forall>seq oper.
    Broadcast ((i, seq), oper) \<in> set (op_history (fst (snd conf i))) \<longrightarrow>
    seq \<le> length (filter_bcast (fst (snd conf i)))", force)
  apply((rule allI)+, rule impI)
  apply(subgoal_tac "\<exists>idx. idx < length (filter_bcast (fst (snd conf i))) \<and> 
    msg_id (filter_bcast (fst (snd conf i)) ! idx) = (i, seq)")
  apply(erule exE, erule conjE, simp add: broadcast_msg_id)
  apply(subgoal_tac "\<exists>m \<in> set (filter_bcast (fst (snd conf i))). msg_id m = (i, seq)")
  using set_elem_nth apply fastforce
  apply(metis op_history_filter_bcast)
done

lemma (in cbcast_protocol) local_deliver_distinct:
  assumes "execution conf"
    and "msg_id msg = next_msgid i (snd conf i)"
  shows "Deliver (msg_id msg, msg_op msg) \<notin> set (op_history (fst (snd conf i)))"
  using assms apply -
(*  apply(frule_tac i=i and P="\<lambda>conf hist. Deliver msg \<notin> set hist"
        in history_invariant, simp_all) *)
  sorry

lemma (in cbcast_protocol) remote_deliver_distinct:
  assumes "execution conf"
    and "causally_ready (snd conf i) msg"
  shows "Deliver (msg_id msg, msg_op msg) \<notin> set (op_history (fst (snd conf i)))"
  sorry

lemma (in cbcast_protocol) histories_distinct:
  assumes "execution conf"
  shows "distinct (op_history (fst (snd conf i)))"
  using assms apply -
  apply(drule_tac i=i and P="\<lambda>c hist. distinct (op_history hist)" in history_invariant)
  apply(simp add: op_history_def, simp) prefer 3 apply assumption
  apply(subgoal_tac "Broadcast (msg_id msg, msg_op msg) \<notin> set (op_history hist)")
  prefer 2 using broadcast_distinct apply blast
  apply(subgoal_tac "Deliver (msg_id msg, msg_op msg) \<notin> set (op_history hist)")
  prefer 2 using local_deliver_distinct apply blast
  apply(subgoal_tac "op_history (hist @ [Broadcast msg, Deliver msg]) =
    op_history hist @ [Broadcast (msg_id msg, msg_op msg), Deliver (msg_id msg, msg_op msg)]")
  apply(simp, metis (no_types, lifting) op_history_append op_history_broadcast op_history_deliver
    append_butlast_last_id butlast.simps(2) last_ConsL last_ConsR list.simps(3))
  apply(subgoal_tac "Deliver (msg_id msg, msg_op msg) \<notin> set (op_history hist)")
  prefer 2 using remote_deliver_distinct apply blast
  apply(subgoal_tac "op_history (hist @ [Deliver msg]) =
    op_history hist @ [Deliver (msg_id msg, msg_op msg)]")
  apply(simp, simp add: op_history_append op_history_deliver)
done

(*
  assumes delivery_has_a_cause: "\<lbrakk> Deliver m \<in> set (history i) \<rbrakk> \<Longrightarrow>
                                    \<exists>j. Broadcast m \<in> set (history j)"
      and deliver_locally: "\<lbrakk> Broadcast m \<in> set (history i) \<rbrakk> \<Longrightarrow>
                                    Broadcast m \<sqsubset>\<^sup>i Deliver m"

lemma (in cbcast_protocol) causal_delivery:
  assumes "Deliver m2 \<in> set (history j)"
    and "hb m1 m2"
  shows "Deliver m1 \<sqsubset>\<^sup>j Deliver m2"

  assumes broadcast_only_valid_msgs: "pre @ [Broadcast m] prefix of i \<Longrightarrow>
             \<exists>state. apply_operations pre = Some state \<and> valid_msg state m"
*)

(* This locale is separate from cbcast_protocol really only because
   cbcast_protocol uses a abstract 'nodeid to identify nodes,
   while the axiomatic network model uses nat. Could simplify this
   by changing the network model to use 'nodeid as well. *)
locale cbcast_with_ops = cbcast_protocol _ _ valid_ops
  for valid_ops :: "nat \<Rightarrow> 'state \<Rightarrow> 'op set"
begin
  sublocale axiomatic: network_with_constrained_ops
    "\<lambda>i. op_history (history i)" interp initial_state valid_op_msgs
  apply standard
  apply(simp add: valid_execution history_def histories_distinct)
  prefer 3 apply(simp add: op_history_def msg_id_unique)
  oops
end

end